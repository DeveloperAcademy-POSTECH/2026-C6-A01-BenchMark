//
//  OiSeedCucumberModel.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/12/26.
//

import RealityKit
import UIKit

/// Builds the preview in metres, facing +Z with the soles at y = 0.
@MainActor enum OiSeedCucumberModel {
    private static let metresPerPixel: Float = 1.5 / 1_470
    private static let axis = Float(OiSeedCucumberAppearance.bodyPivot.x)
    private static let floor = Float(OiSeedCucumberAppearance.bodyPivot.y)
    private static let skin = UIColor(red: 0.59, green: 0.74, blue: 0.17, alpha: 1)
    private static let leaf = UIColor(red: 0.22, green: 0.38, blue: 0.10, alpha: 1)
    private static let faceInk = UIColor(red: 0.10, green: 0.19, blue: 0.07, alpha: 1)
    private static var skinTexture: TextureResource?

    static func make(appearance: OiSeedCucumberAppearance) throws -> Entity {
        let shape = Shape(appearance: appearance)
        let root = Entity()
        root.name = "SeedCucumber"
        root.addChild(try makeBody(shape))

        let ink = material(faceInk, roughness: 0.52)
        for (name, layer) in [("LeftEye", OiSeedCucumberLayer.leftEye), ("RightEye", .rightEye)] {
            let frame = appearance.faceFrame(layer)
            root.addChild(try makeEye(name: name, frame: frame, shape: shape, material: ink))
        }
        root.addChild(try makeMouth(frame: appearance.faceFrame(.mouth), shape: shape, material: ink))
        root.addChild(try makeStem(appearance))
        try addLimbs(to: root, shape: shape)
        return root
    }

    private struct Shape {
        let appearance: OiSeedCucumberAppearance
        private static let top: Float = 156
        private static let bottom: Float = 1264

        func artPoint(_ x: Float, _ y: Float, depth: Float = 0) -> SIMD3<Float> {
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y)).applying(appearance.bodyTransform)
            return OiSeedCucumberModel.position(x: Float(point.x), y: Float(point.y), depth: depth)
        }

        func section(at sourceY: Float) -> (center: Float, radius: Float, depth: Float) {
            let t = min(1, max(0, (sourceY - Self.top) / (Self.bottom - Self.top)))
            let roundEnds = pow(max(0, 4 * t * (1 - t)), 0.31)
            let center = axis + 9 * sin(t * 2 * .pi)
            let asymmetry = 0.92 + 0.13 * t + 0.025 * sin(t * 6 * .pi)
            let width = Float(appearance.bodyWidth)
            let radius = 252 * roundEnds * asymmetry * width
            return (axis + (center - axis) * width, radius, radius * 0.74)
        }

        func bodyPoint(latitude: Float, longitude: Float) -> SIMD3<Float> {
            let sourceY = Self.top + (Self.bottom - Self.top) * (1 - cos(latitude)) / 2
            let y = floor + (sourceY - floor) * Float(appearance.bodyHeight)
            let section = section(at: sourceY)
            return position(x: section.center + section.radius * sin(longitude), y: y,
                            depth: section.depth * cos(longitude))
        }

        func front(x: Float, y: Float, rise: Float = 0) -> SIMD3<Float> {
            let sourceY = floor + (y - floor) / Float(appearance.bodyHeight)
            let section = section(at: sourceY)
            let horizontal = (x - section.center) / max(1, section.radius)
            let magnitude = abs(horizontal)
            // Near the silhouette, ease features around the skin instead of letting
            // a large or widely spaced feature extend past the body.
            let projected = magnitude <= 0.70 ? magnitude : 0.70 + 0.27 * (1 - exp(-(magnitude - 0.70) / 0.27))
            let across = horizontal < 0 ? -projected : projected
            let depth = section.depth * sqrt(max(0, 1 - across * across)) + rise
            return position(x: section.center + across * section.radius, y: y, depth: depth)
        }
    }

    private static func position(x: Float, y: Float, depth: Float) -> SIMD3<Float> {
        SIMD3<Float>(x - axis, floor - y, depth) * metresPerPixel
    }

    private static func makeBody(_ shape: Shape) throws -> ModelEntity {
        let latitudes = 56
        let longitudes = 64
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        let sample: Float = 0.002
        for row in 0...latitudes {
            let v = Float(row) / Float(latitudes)
            let latitude = v * .pi
            for column in 0...longitudes {
                let u = Float(column) / Float(longitudes)
                let longitude = (u * 2 - 1) * .pi
                positions.append(shape.bodyPoint(latitude: latitude, longitude: longitude))
                if row == 0 || row == latitudes {
                    normals.append([0, row == 0 ? 1 : -1, 0])
                } else {
                    let down = shape.bodyPoint(latitude: latitude + sample, longitude: longitude)
                        - shape.bodyPoint(latitude: latitude - sample, longitude: longitude)
                    let right = shape.bodyPoint(latitude: latitude, longitude: longitude + sample)
                        - shape.bodyPoint(latitude: latitude, longitude: longitude - sample)
                    normals.append(simd_normalize(simd_cross(down, right)))
                }
                coordinates.append([u, 1 - v])
            }
        }
        var descriptor = MeshDescriptor(name: "Body")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(ringIndices(rows: latitudes, sides: longitudes, closesEnds: true))
        let mesh = try MeshResource.generate(from: [descriptor])
        var bodyMaterial = material(.white, roughness: 0.81)
        bodyMaterial.baseColor = .init(tint: .white, texture: .init(try cucumberSkinTexture()))
        let body = ModelEntity(mesh: mesh, materials: [bodyMaterial])
        body.name = "Body"
        return body
    }

    private static func makeEye(name: String, frame: CGRect, shape: Shape,
                                material: PhysicallyBasedMaterial) throws -> ModelEntity {
        let rows = 10
        let sides = 24
        var positions: [SIMD3<Float>] = []
        let radiusX = Float(frame.width) * 0.38
        let radiusY = Float(frame.height) * 0.40
        let radiusZ = min(radiusX, radiusY) * 0.30
        for row in 0...rows {
            let latitude = Float(row) / Float(rows) * .pi
            for side in 0...sides {
                let longitude = Float(side) / Float(sides) * 2 * .pi
                let x = Float(frame.midX) + radiusX * sin(latitude) * sin(longitude)
                let y = Float(frame.midY) - radiusY * cos(latitude)
                positions.append(shape.front(x: x, y: y, rise: radiusZ * sin(latitude) * cos(longitude)))
            }
        }
        return try meshEntity(name: name, positions: positions,
                              indices: ringIndices(rows: rows, sides: sides, closesEnds: true), material: material)
    }

    private static func makeMouth(frame: CGRect, shape: Shape,
                                  material: PhysicallyBasedMaterial) throws -> ModelEntity {
        var samples: [TubeSample] = []
        for index in 0...20 {
            let t = Float(index) / 20
            let remaining = 1 - t
            // Rounded, slightly asymmetrical smile in the same art frame as the crop.
            let x = -0.37 * remaining * remaining * remaining - 0.22 * 3 * remaining * remaining * t
                + 0.12 * 3 * remaining * t * t + 0.36 * t * t * t
            let y = -0.28 * remaining * remaining * remaining + 0.34 * 3 * remaining * remaining * t
                + 0.39 * 3 * remaining * t * t + 0.02 * t * t * t
            let center = shape.front(x: Float(frame.midX) + x * Float(frame.width),
                                     y: Float(frame.midY) + y * Float(frame.height))
            let cap = index == 0 || index == 20
            let radius = cap ? 0 : Float(frame.height) * (index == 1 || index == 19 ? 0.082 : 0.13)
            samples.append(TubeSample(center: center, radius: radius * metresPerPixel))
        }
        return try tubeEntity(name: "Mouth", samples: samples, material: material)
    }

    private static func makeStem(_ appearance: OiSeedCucumberAppearance) throws -> ModelEntity {
        let base = OiSeedCucumberAppearance.stemBase
        let tip = OiSeedCucumberAppearance.stemDefaultTip
        var samples: [TubeSample] = []
        for index in 0...20 {
            let t = CGFloat(index) / 20
            let remaining = 1 - t
            let x = base.x * remaining * remaining * remaining + (base.x + 12) * 3 * remaining * remaining * t
                + (tip.x - 28) * 3 * remaining * t * t + tip.x * t * t * t
            let y = base.y * remaining * remaining * remaining + (base.y - 68) * 3 * remaining * remaining * t
                + (tip.y - 21) * 3 * remaining * t * t + tip.y * t * t * t
            let point = appearance.stemPoint(for: CGPoint(x: x, y: y))
            let center = position(x: Float(point.x), y: Float(point.y), depth: 13 * sin(Float(t) * .pi))
            let radius = index == 0 || index == 20 ? 0 : (28 - 11 * Float(t)) * min(1, Float(20 - index) / 3)
            samples.append(TubeSample(center: center, radius: radius * metresPerPixel))
        }
        return try tubeEntity(name: "Stem", samples: samples, material: material(leaf, roughness: 0.76))
    }

    private static func addLimbs(to root: Entity, shape: Shape) throws {
        let armMaterial = material(skin, roughness: 0.78)
        let handMaterial = material(leaf, roughness: 0.78)
        let width = Float(shape.appearance.bodyWidth)
        let height = Float(shape.appearance.bodyHeight)
        for (side, sign): (String, Float) in [("Left", -1), ("Right", 1)] {
            let shoulder = shape.artPoint(axis + sign * 211, 805, depth: 1)
            let elbow = shape.artPoint(axis + sign * 277, 914, depth: 9)
            let wrist = shape.artPoint(axis + sign * 332, 1000, depth: 14)
            let hand = shape.artPoint(axis + sign * 347, 1036, depth: 16)
            root.addChild(try tubeEntity(name: side + "Arm", samples: [
                .init(center: shoulder, radius: 0),
                .init(center: shoulder + (elbow - shoulder) * 0.10, radius: 0.034 * width),
                .init(center: elbow, radius: 0.028 * width),
                .init(center: wrist, radius: 0.024 * width),
                .init(center: hand, radius: 0)
            ], material: armMaterial))
            root.addChild(ellipsoid(name: side + "Hand", center: hand,
                                   radii: [0.052 * width, 0.053 * height, 0.046 * width], material: handMaterial))

            let legTop = shape.artPoint(axis + sign * 107, 1198, depth: -8)
            let ankle = shape.artPoint(axis + sign * 113, 1500, depth: -7)
            root.addChild(try tubeEntity(name: side + "Leg", samples: [
                .init(center: legTop, radius: 0),
                .init(center: legTop + (ankle - legTop) * 0.12, radius: 0.038 * width),
                .init(center: ankle - (ankle - legTop) * 0.12, radius: 0.029 * width),
                .init(center: ankle, radius: 0)
            ], material: armMaterial))
            let footRadiusY = 0.044 * height
            let footCenter = SIMD3<Float>(ankle.x + sign * 0.009 * width, footRadiusY, ankle.z + 0.024)
            root.addChild(ellipsoid(name: side + "Foot", center: footCenter,
                                   radii: [0.072 * width, footRadiusY, 0.083 * width], material: handMaterial))
        }
    }

    private static func ellipsoid(name: String, center: SIMD3<Float>, radii: SIMD3<Float>,
                                  material: PhysicallyBasedMaterial) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
        entity.name = name
        entity.position = center
        entity.scale = radii
        return entity
    }

    private struct TubeSample {
        let center: SIMD3<Float>
        let radius: Float
    }

    private static func tubeEntity(name: String, samples: [TubeSample],
                                   material: PhysicallyBasedMaterial) throws -> ModelEntity {
        let sides = 16
        var positions: [SIMD3<Float>] = []
        for (index, sample) in samples.enumerated() {
            let previous = samples[max(0, index - 1)].center
            let next = samples[min(samples.count - 1, index + 1)].center
            let tangent = simd_normalize(next - previous)
            let across = simd_normalize(simd_cross(tangent, SIMD3<Float>(0, 0, 1)))
            let normal = simd_cross(across, tangent)
            for side in 0...sides {
                let angle = Float(side) / Float(sides) * 2 * .pi
                let direction = cos(angle) * across + sin(angle) * normal
                positions.append(sample.center + direction * sample.radius)
            }
        }
        return try meshEntity(name: name, positions: positions,
                              indices: ringIndices(rows: samples.count - 1, sides: sides, closesEnds: true),
                              material: material)
    }

    private static func ringIndices(rows: Int, sides: Int, closesEnds: Bool) -> [UInt32] {
        var indices: [UInt32] = []
        for row in 0..<rows {
            for side in 0..<sides {
                let here = UInt32(row * (sides + 1) + side)
                let below = here + UInt32(sides + 1)
                if !closesEnds || row > 0 { indices += [here, below, here + 1] }
                if !closesEnds || row < rows - 1 { indices += [here + 1, below, below + 1] }
            }
        }
        return indices
    }

    private static func meshEntity(name: String, positions: [SIMD3<Float>], indices: [UInt32],
                                   material: PhysicallyBasedMaterial) throws -> ModelEntity {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        return entity
    }

    private static func material(_ color: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        return material
    }

    private static func cucumberSkinTexture() throws -> TextureResource {
        if let skinTexture { return skinTexture }
        let size = 256
        var rgba = [UInt8]()
        rgba.reserveCapacity(size * size * 4)
        let light = SIMD3<Float>(158, 188, 49)
        let dark = SIMD3<Float>(66, 107, 30)
        for row in 0..<size {
            let v = Float(row) / Float(size)
            for column in 0..<size {
                let u = Float(column) / Float(size)
                let angle = u * 2 * .pi
                let wander = 0.14 * sin(v * 31 + sin(angle * 3))
                    + 0.06 * cos(v * 74 - angle * 2)
                let bands = cos(angle * 7 + 2.2 + wander)
                let edge = 0.80 + 0.06 * sin(v * 19 + angle * 4)
                let stripe = min(1, max(0, (bands - edge) * 11))
                let grain = 3 * sin(angle * 73 + v * 317) * cos(angle * 61 - v * 271)
                let texture = light + (dark - light) * stripe + SIMD3<Float>(repeating: grain)
                rgba.append(UInt8(clamping: Int(texture.x)))
                rgba.append(UInt8(clamping: Int(texture.y)))
                rgba.append(UInt8(clamping: Int(texture.z)))
                rgba.append(255)
            }
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw CocoaError(.fileReadCorruptFile) }
        let texture = try TextureResource(image: image, options: .init(semantic: .color))
        skinTexture = texture
        return texture
    }
}
