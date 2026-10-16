import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit

@main
struct ARBackgroundChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() throws {
        let identity = ARBackgroundGeometry.cameraToAnalysis(imageSize: CGSize(width: 1920, height: 1080),
            analysisSize: CGSize(width: 512, height: 288), displayTransform: .identity)
        let p = CGPoint(x: 960, y: 540).applying(identity)
        check(abs(p.x - 256) < 0.001 && abs(p.y - 144) < 0.001, "Camera center must map to preview center")
        let rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        let rotated = ARBackgroundGeometry.cameraToAnalysis(imageSize: CGSize(width: 1920, height: 1080),
            analysisSize: CGSize(width: 288, height: 512), displayTransform: rotate)
        let corner = CGPoint(x: 0, y: 1080).applying(rotated)
        check(abs(corner.x - 288) < 0.001 && abs(corner.y - 512) < 0.001, "Portrait rotation must preserve top-left conventions")
        for viewport in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let size = ARBackgroundGeometry.analysisSize(for: viewport)
            check(max(size.width, size.height) == 512, "Bounded analysis size")
            let scale = ARBackgroundGeometry.backgroundScale(image: CGSize(width: 1086, height: 1448), viewport: viewport)
            check(scale.width <= 1 && scale.height <= 1, "Aspect fill may not stretch the background")
        }
        let first: [UInt8] = [0, 1, 1, 0, 1, 1]
        check(ARBenchMaskSelection.instance(at: CGPoint(x: 0.5, y: 0.25), labels: first, width: 3, height: 2) == 1, "Tap selection")
        check(ARBenchMaskSelection.instance(at: .zero, labels: first, width: 3, height: 2) == nil, "Background is not a bench")
        check(ARBenchMaskSelection.instance(at: CGPoint(x: 1, y: 1), labels: first, width: 3, height: 2) == nil, "Reject out-of-bounds tap")
        check(ARBenchMaskSelection.matchingInstance(labels: [0, 4, 4, 0, 4, 4], previous: first.map { $0 == 1 }) == 4, "IDs may change between frames")
        check(ARBenchMaskSelection.matchingInstance(labels: [3, 0, 0, 3, 0, 0], previous: first.map { $0 == 1 }) == nil, "Do not switch to a disjoint object")
        check(ARBackgroundGeometry.clearDepth(projectionZ: -1.001, projectionW: -1) == 1, "Finite forward Z clear depth")
        check(ARBackgroundGeometry.clearDepth(projectionZ: 0.001, projectionW: -1) == 0, "Finite reversed Z clear depth")
        try checkGPU()
        print("PASS: camera geometry, bench selection, GPU composite, passthrough and saved image orientation")
    }

    static func checkGPU() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "GPU checks need Metal", code: 1)
        }
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "oiStadiumComposite")!)
        func texture(_ format: MTLPixelFormat, _ usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 2, height: 2, mipmapped: false)
            desc.usage = usage
            desc.storageMode = format == .depth32Float ? .private : .shared
            return device.makeTexture(descriptor: desc)!
        }
        let scene = texture(.rgba32Float)
        let depth = texture(.depth32Float)
        let mask = texture(.r32Float)
        let background = texture(.rgba32Float)
        let output = texture(.rgba32Float)
        let region = MTLRegionMake2D(0, 0, 2, 2)
        let colors: [Float] = [1,0,0,1, 0,0,1,1, 1,1,0,1, 1,0,1,1]
        let green: [Float] = Array(repeating: [Float](arrayLiteral: 0,1,0,1), count: 4).flatMap { $0 }
        let masks: [Float] = [1,0,0.5,0]
        colors.withUnsafeBytes { scene.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 32) }
        green.withUnsafeBytes { background.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 32) }
        masks.withUnsafeBytes { mask.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
        let depthBuffer = device.makeBuffer(length: 512)!
        let depthValues = depthBuffer.contents().assumingMemoryBound(to: Float.self)
        depthValues[0] = 0; depthValues[1] = 0.4; depthValues[64] = 0; depthValues[65] = 0
        let upload = queue.makeCommandBuffer()!
        let blit = upload.makeBlitCommandEncoder()!
        blit.copy(from: depthBuffer, sourceOffset: 0, sourceBytesPerRow: 256, sourceBytesPerImage: 512,
                  sourceSize: MTLSize(width: 2, height: 2, depth: 1), to: depth,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding(); upload.commit(); upload.waitUntilCompleted()
        struct Uniforms { var scale: SIMD2<Float>; var far: Float; var enabled: Float }
        func render(enabled: Float) throws -> [Float] {
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(pipeline)
            [scene, depth, mask, background, output].enumerated().forEach { encoder.setTexture($0.element, index: $0.offset) }
            var uniforms = Uniforms(scale: SIMD2(1,1), far: 0, enabled: enabled)
            encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.dispatchThreads(MTLSize(width: 2, height: 2, depth: 1), threadsPerThreadgroup: MTLSize(width: 2, height: 2, depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            var result = [Float](repeating: 0, count: 16)
            result.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 32, from: region, mipmapLevel: 0) }
            return result
        }
        let pixels = try render(enabled: 1)
        check(pixels[0] == 1 && pixels[1] == 0, "Keep selected real foreground")
        check(pixels[6] == 1, "Keep virtual character using depth")
        check(abs(pixels[8] - 0.5) < 0.001 && pixels[9] == 1, "Soft mask boundary")
        check(pixels[12] == 0 && pixels[13] == 1, "Replace background")
        // Metal rows are top-left. Verify the exact conversion used for capture
        // so portrait photos cannot silently be saved upside down.
        let image = CIImage(mtlTexture: output, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])!.oriented(.downMirrored)
        let cg = CIContext().createCGImage(image, from: image.extent)!
        let roundTrip = try MTKTextureLoader(device: device).newTexture(cgImage: cg,
            options: [.origin: MTKTextureLoader.Origin.topLeft, .SRGB: false, .textureStorageMode: MTLStorageMode.shared.rawValue])
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes.withUnsafeMutableBytes { roundTrip.getBytes($0.baseAddress!, bytesPerRow: 8, from: region, mipmapLevel: 0) }
        // Loader uses RGBA8; first row must remain red, blue.
        check(roundTrip.pixelFormat == .rgba8Unorm && bytes[0] > 240 && bytes[2] < 10 && bytes[6] > 240, "Capture preserves top row")
        let bypass = try render(enabled: 0)
        check(bypass == colors, "No mask must show unmodified camera")
    }
}
