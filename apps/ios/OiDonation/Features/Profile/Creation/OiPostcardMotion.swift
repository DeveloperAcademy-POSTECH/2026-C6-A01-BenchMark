//
//  OiPostcardMotion.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import CoreMotion
import simd
import SwiftUI
import UIKit

struct OiPostcardTilt: Equatable, Sendable {
    var x: Double
    var y: Double

    static let zero = OiPostcardTilt(x: 0, y: 0)

    func oriented(for orientation: UIInterfaceOrientation) -> OiPostcardTilt {
        switch orientation {
        case .portrait: return self
        case .portraitUpsideDown: return OiPostcardTilt(x: -x, y: -y)
        case .landscapeLeft: return OiPostcardTilt(x: -y, y: x)
        case .landscapeRight: return OiPostcardTilt(x: y, y: -x)
        default: return .zero
        }
    }
}

/// Device-relative rotation keeps the card at rest in the user's current holding position.
struct OiPostcardMotionFilter {
    private var reference: simd_quatd?
    private var lastTimestamp: TimeInterval?
    private(set) var tilt = OiPostcardTilt.zero

    mutating func update(quaternion: SIMD4<Double>, timestamp: TimeInterval) -> OiPostcardTilt? {
        let lengthSquared = simd_length_squared(quaternion)
        guard timestamp.isFinite, quaternion.x.isFinite, quaternion.y.isFinite,
              quaternion.z.isFinite, quaternion.w.isFinite,
              lengthSquared.isFinite, lengthSquared > 0.000001 else { return nil }
        let current = simd_normalize(simd_quatd(vector: quaternion))
        guard let reference, let lastTimestamp else {
            reference = current
            lastTimestamp = timestamp
            tilt = .zero
            return tilt
        }
        guard timestamp > lastTimestamp else { return tilt }
        self.lastTimestamp = timestamp

        var relative = simd_normalize(reference.inverse * current)
        // q and -q represent the same attitude. Always take the shorter rotation.
        if relative.real < 0 { relative = simd_quatd(vector: -relative.vector) }
        let magnitude = simd_length(relative.imag)
        let rotation = magnitude > 0.000001
            ? relative.imag * (2 * atan2(magnitude, relative.real) / magnitude)
            : .zero
        let scale = 180 / Double.pi * 0.2
        let target = OiPostcardTilt(x: min(4, max(-4, rotation.x * scale)),
                                   y: min(4, max(-4, rotation.y * scale)))
        let smoothing = 1 - exp(-min(timestamp - lastTimestamp, 1) / 0.12)
        tilt.x += (target.x - tilt.x) * smoothing
        tilt.y += (target.y - tilt.y) * smoothing
        return tilt
    }

    mutating func reset() {
        reference = nil
        lastTimestamp = nil
        tilt = .zero
    }
}

@MainActor @Observable
final class OiPostcardMotionController {
    private(set) var tilt = OiPostcardTilt.zero
    private let manager = CMMotionManager()
    private var session: UUID?
    private var sampleContinuation: AsyncStream<Sample>.Continuation?
    @ObservationIgnored weak var anchor: UIView?

    private struct Sample: Sendable {
        let quaternion: SIMD4<Double>
        let timestamp: TimeInterval
    }

    func track() async {
        guard !Task.isCancelled else { return }
        stop()
        guard manager.isDeviceMotionAvailable else { return }
        let currentSession = UUID()
        session = currentSession
        let (samples, continuation) = AsyncStream<Sample>.makeStream(bufferingPolicy: .bufferingNewest(1))
        sampleContinuation = continuation
        defer {
            continuation.finish()
            // A cancelled reader must not stop a newer reader that already resumed.
            if session == currentSession { stop() }
        }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { motion, error in
            guard error == nil, let motion else { continuation.finish(); return }
            let quaternion = motion.attitude.quaternion
            continuation.yield(Sample(quaternion: SIMD4(quaternion.x, quaternion.y, quaternion.z, quaternion.w),
                                      timestamp: motion.timestamp))
        }
        var filter = OiPostcardMotionFilter()
        var lastOrientation = UIInterfaceOrientation.unknown
        for await sample in samples {
            guard !Task.isCancelled, session == currentSession else { break }
            let orientation = anchor?.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .unknown
            if orientation != lastOrientation {
                filter.reset()
                lastOrientation = orientation
            }
            guard let next = filter.update(quaternion: sample.quaternion, timestamp: sample.timestamp) else { break }
            tilt = next.oriented(for: orientation)
        }
    }

    func stop() {
        session = nil
        manager.stopDeviceMotionUpdates()
        sampleContinuation?.finish()
        sampleContinuation = nil
        tilt = .zero
    }
}

struct OiPostcardMotion: ViewModifier {
    let controller: OiPostcardMotionController
    let isEnabled: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldRun: Bool { isEnabled && scenePhase == .active && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(controller.tilt.x), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(controller.tilt.y), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .background { OiPostcardMotionAnchor(controller: controller).allowsHitTesting(false) }
            .task(id: shouldRun) {
                if shouldRun { await controller.track() } else { controller.stop() }
            }
            .onChange(of: shouldRun) { _, active in
                if !active { controller.stop() }
            }
            .onDisappear { controller.stop() }
    }
}

/// Reads the orientation of this card's own scene, including when rotation lock is enabled.
private struct OiPostcardMotionAnchor: UIViewRepresentable {
    let controller: OiPostcardMotionController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        controller.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        controller.anchor = view
    }
}
