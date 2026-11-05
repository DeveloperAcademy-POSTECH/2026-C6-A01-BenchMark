import ARKit
import CoreImage
import MetalKit
import QuartzCore
import RealityKit
import Vision

/// The lock protects the small handoff state. Vision and image conversion run
/// on one worker; RealityKit encodes the composite on its own render callback.
nonisolated final class ARStadiumBackgroundService: @unchecked Sendable {
    private struct Packet {
        let texture: MTLTexture
        let timestamp: TimeInterval
        let camera: simd_float4x4
    }
    // Owned copy is read only after its GPU command buffer completes.
    private struct CaptureTexture: @unchecked Sendable { let value: MTLTexture }
    private struct Capture {
        let id: UUID
        let completion: @Sendable (CGImage?) -> Void
        var submitted = false
    }
    private struct Uniforms {
        var backgroundScale: SIMD2<Float>
        var farDepth: Float
        var enabled: Float
    }
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "오이기부.stadium.vision", qos: .userInitiated)
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let backgroundImage: CGImage?
    private let onUpdate: @MainActor @Sendable (String, Bool) -> Void
    private var enabled = false
    private var generation = 0
    private var busy = false
    private var lastSubmitted: TimeInterval = 0
    private var currentTimestamp: TimeInterval = 0
    private var layout = CGSize.zero
    private var displayTransform = CGAffineTransform.identity
    private var currentCamera = matrix_identity_float4x4
    private let peopleRequest = VNGeneratePersonSegmentationRequest()
    private var selection: CGPoint?
    private var previousBench: [Bool]?
    private var packet: Packet?
    private var device: MTLDevice?
    private var pipeline: MTLComputePipelineState?
    private var backgroundTexture: MTLTexture?
    private var pendingCapture: Capture?
    private var lastStatus = ""

    init(background: CGImage?, onUpdate: @escaping @MainActor @Sendable (String, Bool) -> Void) {
        backgroundImage = background
        self.onUpdate = onUpdate
        peopleRequest.qualityLevel = .balanced
        peopleRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    func setEnabled(_ value: Bool) {
        let cancelled = synchronized { () -> Capture? in
            enabled = value
            generation += 1
            packet = nil
            previousBench = nil
            selection = nil
            lastSubmitted = 0
            lastStatus = ""
            let pending = pendingCapture
            pendingCapture = nil
            return pending
        }
        cancelled?.completion(nil)
        if value && synchronized({ pipeline == nil }) {
            report("경기장 합성을 준비하지 못했습니다. 원본 배경을 사용해 주세요.", ready: false)
            return
        }
        report(value ? "남길 벤치를 화면에서 터치하세요. 사람은 자동으로 남깁니다." : "", ready: false)
    }

    func selectBench(at point: CGPoint) {
        synchronized {
            generation += 1
            selection = point
            previousBench = nil
            packet = nil
        }
        report("선택한 벤치를 분리하는 중…", ready: false)
    }

    func reselectBench() { setEnabled(true) }

    var hasFreshMask: Bool {
        synchronized {
            guard enabled, let packet else { return false }
            return currentTimestamp - packet.timestamp <= 0.6 && cameraMatches(packet.camera, currentCamera)
        }
    }

    func prepare(device: MTLDevice) {
        guard !synchronized({ pipeline != nil }) else { return }
        do {
            guard let backgroundImage,
                  let url = Bundle.main.url(forResource: "ARStadiumComposite", withExtension: "metalSource") else {
                report("경기장 리소스를 불러오지 못했습니다. 원본 배경을 사용해 주세요.", ready: false)
                return
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            let library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "oiStadiumComposite") else { return }
            let pipeline = try device.makeComputePipelineState(function: function)
            let texture = try MTKTextureLoader(device: device).newTexture(cgImage: backgroundImage,
                options: [.SRGB: true, .origin: MTKTextureLoader.Origin.topLeft,
                          .textureUsage: MTLTextureUsage.shaderRead.rawValue])
            synchronized {
                self.device = device
                self.pipeline = pipeline
                backgroundTexture = texture
            }
        } catch {
            report("이 기기에서 경기장 합성을 준비하지 못했습니다. 원본 배경을 사용해 주세요.", ready: false)
        }
    }

    /// Called on the ARSession delegate's main queue. Never queues a second
    /// frame while Vision is busy, and invalidates masks after viewport changes.
    func submit(_ frame: ARFrame, viewport: CGSize, orientation: UIInterfaceOrientation) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let transform = frame.displayTransform(for: orientation, viewportSize: viewport)
        let input = synchronized { () -> (Int, MTLDevice, CGPoint?, [Bool]?)? in
            currentTimestamp = frame.timestamp
            currentCamera = frame.camera.transform
            if layout != viewport || !approximatelyEqual(displayTransform, transform) {
                generation += 1
                layout = viewport
                displayTransform = transform
                packet = nil
                previousBench = nil
                selection = nil
            }
            guard enabled, !busy, frame.timestamp - lastSubmitted >= 0.1, let device, pipeline != nil else { return nil }
            busy = true
            lastSubmitted = frame.timestamp
            return (generation, device, selection, previousBench)
        }
        guard let (token, device, point, previous) = input else { return }
        let timestamp = frame.timestamp
        worker.async { [self] in
            autoreleasepool {
                defer { synchronized { busy = false } }
                do {
                    let size = ARBackgroundGeometry.analysisSize(for: viewport)
                    let raw = CIImage(cvPixelBuffer: frame.capturedImage)
                    let image = raw.transformed(by: ARBackgroundGeometry.cameraToAnalysis(
                        imageSize: raw.extent.size, analysisSize: size, displayTransform: transform))
                    let bounds = CGRect(origin: .zero, size: size)
                    guard let cgImage = imageContext.createCGImage(image, from: bounds) else { throw Failure.image }
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                    let foreground = VNGenerateForegroundInstanceMaskRequest()
                    // Bench selection is explicit: a prominent tree must not
                    // silently be treated as the bench just because it is large.
                    guard point != nil || previous != nil else {
                        report("남길 벤치를 화면에서 터치하세요. 사람은 자동으로 남깁니다.", ready: false, token: token)
                        return
                    }
                    try handler.perform([foreground, peopleRequest])
                    guard let observation = foreground.results?.first else { throw Failure.noBench }
                    let instanceBuffer = observation.instanceMask
                    let labels = Self.labels(in: instanceBuffer)
                    let id = point.flatMap {
                        ARBenchMaskSelection.instance(at: $0, labels: labels,
                            width: CVPixelBufferGetWidth(instanceBuffer), height: CVPixelBufferGetHeight(instanceBuffer))
                    } ?? previous.flatMap { ARBenchMaskSelection.matchingInstance(labels: labels, previous: $0) }
                    guard let id else { throw Failure.noBench }
                    let bench = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: id), from: handler)
                    var union = CIImage(cvPixelBuffer: bench)
                    if let personBuffer = peopleRequest.results?.first?.pixelBuffer {
                        let person = CIImage(cvPixelBuffer: personBuffer)
                        let scaled = person.transformed(by: CGAffineTransform(
                            scaleX: union.extent.width / person.extent.width,
                            y: union.extent.height / person.extent.height))
                        union = union.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: scaled])
                    }
                    guard let maskImage = imageContext.createCGImage(union, from: union.extent) else { throw Failure.image }
                    let texture = try MTKTextureLoader(device: device).newTexture(cgImage: maskImage,
                        options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft,
                                  .textureUsage: MTLTextureUsage.shaderRead.rawValue])
                    let accepted = synchronized { () -> Bool in
                        guard enabled, generation == token else { return false }
                        packet = Packet(texture: texture, timestamp: timestamp, camera: frame.camera.transform)
                        previousBench = labels.map { Int($0) == id }
                        selection = nil
                        return currentTimestamp - timestamp <= 0.6 && cameraMatches(frame.camera.transform, currentCamera)
                    }
                    if accepted { report("경기장 배경 · 벤치와 사람 유지 중", ready: true, token: token) }
                    else { report("분리 처리 지연 · 원본 화면을 표시합니다. 천천히 움직여 주세요.", ready: false, token: token) }
                } catch {
                    synchronized { if generation == token { packet = nil } }
                    report("벤치를 인식하지 못했습니다. 벤치 선택을 눌러 다시 터치해 주세요.", ready: false, token: token)
                }
            }
        }
    }

    func render(_ context: RealityKit.ARView.PostProcessContext) {
        let state = synchronized { (enabled, packet, pipeline, backgroundTexture, currentTimestamp, generation, currentCamera) }
        guard state.0 else { copy(context); return }
        guard let pipeline = state.2, let background = state.3,
              let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            copy(context)
            return
        }
        let fresh = state.0 && state.1 != nil && state.4 - state.1!.timestamp <= 0.6
            && cameraMatches(state.1!.camera, state.6)
        let scale = ARBackgroundGeometry.backgroundScale(
            image: CGSize(width: background.width, height: background.height),
            viewport: CGSize(width: context.targetColorTexture.width, height: context.targetColorTexture.height))
        let projection = context.projection
        let far = ARBackgroundGeometry.clearDepth(projectionZ: projection[2][2], projectionW: projection[2][3])
        var uniforms = Uniforms(backgroundScale: SIMD2(Float(scale.width), Float(scale.height)),
                                farDepth: far, enabled: fresh ? 1 : 0)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        encoder.setTexture(context.sourceDepthTexture, index: 1)
        encoder.setTexture(state.1?.texture ?? background, index: 2)
        encoder.setTexture(background, index: 3)
        encoder.setTexture(context.targetColorTexture, index: 4)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        let width = pipeline.threadExecutionWidth
        let group = MTLSize(width: width, height: max(1, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1)
        encoder.dispatchThreads(MTLSize(width: context.targetColorTexture.width,
                                       height: context.targetColorTexture.height, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        if state.0 && !fresh {
            report("벤치 분리 대기 · 원본 화면을 표시합니다.", ready: false, token: state.5)
        }
        if fresh { encodeCapture(context, generation: state.5) }
    }

    /// Capture the *same* postprocessed output as the preview. A raw ARView
    /// snapshot is deliberately not used for the stadium path.
    func captureNextFrame(_ completion: @escaping @Sendable (CGImage?) -> Void) {
        let id = UUID()
        let accepted = synchronized { () -> Bool in
            guard enabled, packet != nil, pendingCapture == nil else { return false }
            pendingCapture = Capture(id: id, completion: completion)
            return true
        }
        guard accepted else { completion(nil); return }
        worker.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finishCapture(id, image: nil) }
    }

    private func encodeCapture(_ context: RealityKit.ARView.PostProcessContext, generation token: Int) {
        let id = synchronized { () -> UUID? in
            guard generation == token, let capture = pendingCapture, !capture.submitted else { return nil }
            pendingCapture?.submitted = true
            return capture.id
        }
        guard let id else { return }
        let source = context.targetColorTexture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat,
            width: source.width, height: source.height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private
        guard let texture = context.device.makeTexture(descriptor: descriptor),
              let blit = context.commandBuffer.makeBlitCommandEncoder() else { finishCapture(id, image: nil); return }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        let ownedTexture = CaptureTexture(value: texture)
        context.commandBuffer.addCompletedHandler { [weak self] command in
            guard let self else { return }
            guard command.status == .completed else { self.finishCapture(id, image: nil); return }
            self.worker.async {
                let valid = self.synchronized { self.generation == token && self.enabled }
                guard valid, let image = CIImage(mtlTexture: ownedTexture.value,
                    options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!]) else {
                    self.finishCapture(id, image: nil); return
                }
                // Metal rows have top-left origin; restore it for UIImage/CGImage.
                let flipped = image.oriented(.downMirrored)
                self.finishCapture(id, image: self.imageContext.createCGImage(flipped, from: flipped.extent))
            }
        }
    }

    private func finishCapture(_ id: UUID, image: CGImage?) {
        let capture = synchronized { () -> Capture? in
            guard pendingCapture?.id == id else { return nil }
            let capture = pendingCapture
            pendingCapture = nil
            return capture
        }
        capture?.completion(image)
    }

    private func copy(_ context: RealityKit.ARView.PostProcessContext) {
        guard let encoder = context.commandBuffer.makeBlitCommandEncoder() else { return }
        encoder.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        encoder.endEncoding()
    }

    private func report(_ text: String, ready: Bool, token: Int? = nil) {
        let current = synchronized { () -> Int? in
            guard token == nil || generation == token, lastStatus != text else { return nil }
            lastStatus = text
            return generation
        }
        guard let current else { return }
        Task { @MainActor [weak self] in
            guard let self, self.synchronized({ self.generation == current }) else { return }
            self.onUpdate(text, ready)
        }
    }

    private static func labels(in buffer: CVPixelBuffer) -> [UInt8] {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return [] }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var result: [UInt8] = []
        result.reserveCapacity(width * height)
        for row in 0..<height {
            let bytes = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
            result.append(contentsOf: UnsafeBufferPointer(start: bytes, count: width))
        }
        return result
    }

    private func cameraMatches(_ previous: simd_float4x4, _ current: simd_float4x4) -> Bool {
        let movement = simd_distance(SIMD3(previous.columns.3.x, previous.columns.3.y, previous.columns.3.z),
                                     SIMD3(current.columns.3.x, current.columns.3.y, current.columns.3.z))
        let rotation = abs(simd_dot(simd_quatf(previous).vector, simd_quatf(current).vector))
        return movement < 0.08 && rotation > cos(Float.pi / 90) // at most four degrees
    }

    private func approximatelyEqual(_ a: CGAffineTransform, _ b: CGAffineTransform) -> Bool {
        zip([a.a, a.b, a.c, a.d, a.tx, a.ty], [b.a, b.b, b.c, b.d, b.tx, b.ty])
            .allSatisfy { abs($0 - $1) < 0.0001 }
    }

    private enum Failure: Error { case image, noBench }
}
