//
//  ARPalmTrackingService.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//  Uses the same Apple Vision hand detector as OiUnityARTest's iOS plugin.
//

import ARKit
import Accelerate
import ImageIO
import QuartzCore
import UIKit
import Vision

/// Reuses ARKit's rear camera; no Unity runtime, second camera, or network image processing.
nonisolated final class ARPalmTrackingService: @unchecked Sendable {
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "com.benchmark.oi.palm.vision", qos: .userInitiated)
    private var gate = ARPalmWorkGate()
    private var layout = CGSize.zero
    private var lastOrientation = 0
    private let request = VNDetectHumanHandPoseRequest()
    private var grayscale: NSMutableData?
    private let onUpdate: @MainActor @Sendable (ARPalmObservation) -> Void
    private let onFailure: @MainActor @Sendable () -> Void

    init(onFailure: @escaping @MainActor @Sendable () -> Void,
         onUpdate: @escaping @MainActor @Sendable (ARPalmObservation) -> Void) {
        self.onUpdate = onUpdate
        self.onFailure = onFailure
        request.maximumHandCount = 1
    }
    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
    func invalidate() { synchronized { gate.invalidate() } }

    func submit(_ frame: ARFrame, viewport: CGSize, orientation: UIInterfaceOrientation,
                interval: TimeInterval) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let token = synchronized {
            if layout != viewport || lastOrientation != orientation.rawValue {
                gate.invalidate(); layout = viewport; lastOrientation = orientation.rawValue
            }
            return gate.begin(at: frame.timestamp, interval: interval)
        }
        guard let token else { return }
        let turns: Int
        let exif: CGImagePropertyOrientation
        switch orientation {
        case .landscapeLeft: turns = 0; exif = .up
        case .landscapeRight: turns = 2; exif = .down
        case .portraitUpsideDown: turns = 3; exif = .left
        default: turns = 1; exif = .right
        }
        let input = Input(buffer: frame.capturedImage,
                          display: frame.displayTransform(for: orientation, viewportSize: viewport),
                          camera: frame.camera.viewMatrix(for: orientation).inverse,
                          projection: frame.camera.projectionMatrix(for: orientation, viewportSize: viewport,
                              zNear: 0.01, zFar: 10).inverse,
                          timestamp: frame.timestamp, turns: turns, exif: exif)
        worker.async { [self] in
            autoreleasepool {
                defer { synchronized { gate.finish(token) } }
                guard synchronized({ gate.accepts(token) }), let image = analysisImage(input.buffer) else { return }
                do {
                    try VNImageRequestHandler(cgImage: image, orientation: input.exif).perform([request])
                    guard let hand = request.results?.first else { return }
                    let names: [VNHumanHandPoseObservation.JointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
                    let joints = names.map { try? hand.recognizedPoint($0) }
                    let points = joints.map { point -> SIMD2<Float> in
                        guard let point else { return [.nan, .nan] }
                        return ARPalmGeometry.viewportPoint(SIMD2(Float(point.location.x), Float(point.location.y)),
                            quarterTurns: input.turns, displayTransform: input.display)
                    }
                    guard let sample = ARPalmGeometry.sample(points: points, confidence: joints.map { $0?.confidence ?? 0 }) else { return }
                    let observation = ARPalmObservation(hand: sample, cameraToWorld: input.camera,
                        inverseProjection: input.projection, timestamp: input.timestamp)
                    let timestamp = input.timestamp
                    Task { @MainActor [weak self] in
                        guard let self, synchronized({ gate.accepts(token) }),
                              ARPalmGeometry.isFresh(sample: timestamp, now: CACurrentMediaTime()) else { return }
                        onUpdate(observation)
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        guard let self, synchronized({ gate.accepts(token) }) else { return }
                        onFailure()
                    }
                }
            }
        }
    }

    /// ARKit supplies bi-planar YCbCr. Downsample only luminance on CPU, without a GPU readback.
    private func analysisImage(_ buffer: CVPixelBuffer) -> CGImage? {
        guard CVPixelBufferGetPlaneCount(buffer) > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let source = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let scale = min(1, 640 / Double(max(width, height)))
        let w = max(1, Int(Double(width) * scale)), h = max(1, Int(Double(height) * scale))
        if grayscale?.length != w * h { grayscale = NSMutableData(length: w * h) }
        guard let grayscale else { return nil }
        var src = vImage_Buffer(data: source, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0))
        var dst = vImage_Buffer(data: grayscale.mutableBytes, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
        guard vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError,
              let provider = CGDataProvider(data: grayscale as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Retain one pixel buffer, not an ARFrame and its entire sensor graph.
    private struct Input: @unchecked Sendable {
        let buffer: CVPixelBuffer
        let display: CGAffineTransform
        let camera: simd_float4x4
        let projection: simd_float4x4
        let timestamp: TimeInterval
        let turns: Int
        let exif: CGImagePropertyOrientation
    }
}
