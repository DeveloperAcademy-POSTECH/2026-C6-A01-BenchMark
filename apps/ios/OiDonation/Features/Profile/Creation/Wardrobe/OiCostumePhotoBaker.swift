//
//  OiCostumePhotoBaker.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/6/26.
//

import Foundation
import CoreGraphics
import MetalKit
import RealityKit

/// A bounded, off-main-thread cache for the currently edited costume only.
actor OiCostumePhotoBaker {
    static let shared = OiCostumePhotoBaker()
    nonisolated struct Manifest: Decodable {
        let version: Int
        let bindings: [Binding]
    }
    nonisolated struct Binding: Decodable, Sendable {
        let paths: [[String]]
        let baseImage: String
        let map: String
        let size: Int
    }
    nonisolated struct Result: Sendable {
        let binding: Binding
        let image: CGImage
    }
    private struct Input {
        let binding: Binding
        let base: MTLTexture
        let coordinates: MTLBuffer
    }
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLComputePipelineState?
    private var cachedName: String?
    private var inputs: [Input] = []

    nonisolated static func resource(_ filename: String) throws -> URL {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "WardrobePhotoUV")
                ?? Bundle.main.url(forResource: name, withExtension: ext) else { throw CocoaError(.fileNoSuchFile) }
        return url
    }

    private func photoTexture(_ image: CGImage, device: MTLDevice) throws -> MTLTexture {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 2048, height <= 1024 else { throw OiPhotoDataError.unreadable }
        var bytes = Data(count: width * height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OiPhotoDataError.unreadable }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw OiPhotoDataError.unreadable }
        bytes.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        return texture
    }

    func bake(_ image: CGImage, resource name: String) throws -> [Result] {
        try Task.checkCancellation()
        if device == nil {
            guard let gpu = MTLCreateSystemDefaultDevice(), let queue = gpu.makeCommandQueue() else {
                throw OiPhotoDataError.unreadable
            }
            // Compile the small bundled kernel once, without a separate Xcode Metal toolchain dependency.
            let source = try String(contentsOf: Self.resource("OiCostumePhotoComposite.metal.txt"), encoding: .utf8)
            let library = try gpu.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "oiCostumePhotoComposite") else { throw OiPhotoDataError.unreadable }
            let pipeline = try gpu.makeComputePipelineState(function: function)
            self.pipeline = pipeline; self.device = gpu; self.queue = queue
        }
        guard let device, let queue, let pipeline else { throw OiPhotoDataError.unreadable }
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue,
                                                      .textureUsage: MTLTextureUsage.shaderRead.rawValue]
        if cachedName != name {
            inputs = []; cachedName = nil
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.resource(name + "-bake.json")))
            guard manifest.version == 1, !manifest.bindings.isEmpty, manifest.bindings.count <= 4 else { throw OiPhotoDataError.unreadable }
            for binding in manifest.bindings {
                guard binding.size == 2048, !binding.paths.isEmpty else { throw OiPhotoDataError.unreadable }
                let compressed = try Data(contentsOf: Self.resource(binding.map))
                let data = try (compressed as NSData).decompressed(using: .zlib) as Data
                guard data.count == binding.size * binding.size * 4,
                      let buffer = data.withUnsafeBytes({ bytes in
                          device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
                      }) else { throw OiPhotoDataError.unreadable }
                let base = try loader.newTexture(URL: Self.resource(binding.baseImage), options: options)
                inputs.append(Input(binding: binding, base: base, coordinates: buffer))
            }
            cachedName = name
        }
        // Normalize even fully transparent/monochrome UIKit images to RGBA8.
        // MTKTextureLoader rejects some empty atlas image representations.
        let photo = try photoTexture(image, device: device)
        var results: [Result] = []
        for input in inputs {
            try Task.checkCancellation()
            let size = input.binding.size
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
            descriptor.usage = [.shaderWrite]; descriptor.storageMode = .shared
            guard let output = device.makeTexture(descriptor: descriptor),
                  let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
                throw OiPhotoDataError.unreadable
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(input.base, index: 0); encoder.setTexture(photo, index: 1); encoder.setTexture(output, index: 2)
            encoder.setBuffer(input.coordinates, offset: 0, index: 0)
            let width = pipeline.threadExecutionWidth
            encoder.dispatchThreads(MTLSize(width: size, height: size, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: max(1, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            guard command.status == .completed else { throw command.error ?? OiPhotoDataError.unreadable }
            try Task.checkCancellation()
            var bytes = Data(count: size * size * 4)
            bytes.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: size * 4,
                from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0) }
            guard let provider = CGDataProvider(data: bytes as CFData),
                  let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw OiPhotoDataError.unreadable }
            results.append(Result(binding: input.binding, image: cg))
        }
        return results
    }
}

/// Retain every original material channel so removing a print restores the source exactly.
private struct OiCostumeOriginalMaterials: Component {
    var materials: [any Material]
}

@MainActor enum OiCostumePhotoMaterial {
    struct Prepared {
        let paths: [[String]]
        let texture: TextureResource
    }
    static func prepare(_ image: CGImage, resource: String) async throws -> [Prepared] {
        let results = try await OiCostumePhotoBaker.shared.bake(image, resource: resource)
        var output: [Prepared] = []
        for result in results {
            try Task.checkCancellation()
            let texture = try await TextureResource(image: result.image, options: .init(semantic: .color, mipmapsMode: .none))
            output.append(Prepared(paths: result.binding.paths, texture: texture))
        }
        return output
    }
    static func restore(_ root: Entity) {
        if let original = root.components[OiCostumeOriginalMaterials.self], var model = root.components[ModelComponent.self] {
            model.materials = original.materials; root.components.set(model)
        }
        for child in root.children { restore(child) }
    }
    static func apply(_ prepared: [Prepared], to root: Entity) throws {
        var targets: [(Entity, TextureResource)] = []
        func find(_ node: Entity, path: [String], suffix: [String]) -> [Entity] {
            let path = path + [node.name]
            if path.suffix(suffix.count).elementsEqual(suffix), node.components[ModelComponent.self] != nil { return [node] }
            return node.children.flatMap { find($0, path: path, suffix: suffix) }
        }
        // Validate all bindings before publishing any material changes.
        for item in prepared {
            for path in item.paths {
                let matches = find(root, path: [], suffix: path)
                guard matches.count == 1, let node = matches.first,
                      let model = node.components[ModelComponent.self], model.materials.count == 1,
                      model.materials[0] is PhysicallyBasedMaterial else { throw OiPhotoDataError.unreadable }
                targets.append((node, item.texture))
            }
        }
        for (node, texture) in targets {
            guard var model = node.components[ModelComponent.self], var material = model.materials.first as? PhysicallyBasedMaterial else { continue }
            if node.components[OiCostumeOriginalMaterials.self] == nil {
                node.components.set(OiCostumeOriginalMaterials(materials: model.materials))
            }
            material.baseColor.texture = .init(texture)
            model.materials = [material]; node.components.set(model)
        }
    }
}
