//
//  OiSeedCucumberStem.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/10/26.
//

import SwiftUI
import UIKit

extension OiSeedCucumberAppearance {
    func drawStem(in artwork: GraphicsContext) {
        let layer = OiSeedCucumberLayer.stem
        let warp = stemWarp
        if stemLength == 1, stemAngle == 0 {
            let root = Self.stemBase
            artwork.draw(Image(layer.asset), in: layer.sourceFrame.offsetBy(
                dx: stemAttachment.x - root.x, dy: stemAttachment.y - root.y
            ))
        } else if let texture = OiSeedCucumberStemTexture.original {
            let pixelScale = abs(artwork.transform.a) * artwork.environment.displayScale
            if let (image, frame) = texture.warped(using: warp, pixelScale: pixelScale) {
                artwork.draw(Image(decorative: image, scale: 1), in: frame)
            }
        }
    }
}

private struct OiSeedCucumberStemTexture {
    private static let frame = OiSeedCucumberLayer.stem.sourceFrame
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        .union(.byteOrder32Big)

    static let original: Self? = {
        guard let source = UIImage(named: OiSeedCucumberLayer.stem.asset)?.cgImage else { return nil }
        let width = source.width
        let height = source.height
        var rgba = Data(count: width * height * 4)
        let decoded = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return decoded ? Self(width: width, height: height, rgba: rgba) : nil
    }()

    private let width: Int
    private let height: Int
    private let rgba: Data

    func warped(using warp: OiSeedCucumberStemWarp, pixelScale: CGFloat) -> (CGImage, CGRect)? {
        let root = OiSeedCucumberAppearance.stemBase
        let crop = Self.frame
        let scale = min(1, max(0.25, pixelScale))
        let extentX = max(abs(crop.minX - root.x), abs(crop.maxX - root.x))
        let extentY = max(abs(crop.minY - root.y), abs(crop.maxY - root.y))
        let extent = Int(ceil(warp.mappedRadius(hypot(extentX, extentY)) * scale)) + 1
        let side = 2 * extent
        let samplesPerPixel = 4
        // Rotation and inverse length depend only on radius, so compute them
        // once per subpixel radial sample and reuse them across the image.
        let inverse = (0...extent * samplesPerPixel).map {
            warp.inverseMultiplier(at: CGFloat($0) / CGFloat(samplesPerPixel) / scale)
        }
        let sourceScaleX = CGFloat(width) / crop.width
        let sourceScaleY = CGFloat(height) / crop.height
        let sourceRootX = (root.x - crop.minX) * sourceScaleX - 0.5
        let sourceRootY = (root.y - crop.minY) * sourceScaleY - 0.5
        var output = Data(count: side * side * 4)
        output.withUnsafeMutableBytes { outputBuffer in
            rgba.withUnsafeBytes { sourceBuffer in
                let destination = outputBuffer.bindMemory(to: UInt8.self)
                let source = sourceBuffer.bindMemory(to: UInt8.self)
                for row in 0..<side {
                    let y = CGFloat(row - extent) + 0.5
                    for column in 0..<side {
                        let x = CGFloat(column - extent) + 0.5
                        let radialIndex = Int((sqrt(x * x + y * y) * CGFloat(samplesPerPixel)).rounded())
                        guard radialIndex < inverse.count else { continue }
                        let sample = inverse[radialIndex]
                        let sourceX = sourceRootX + (sample.cosine * x - sample.sine * y) * sourceScaleX / scale
                        let sourceY = sourceRootY + (sample.sine * x + sample.cosine * y) * sourceScaleY / scale
                        guard sourceX >= 0, sourceY >= 0, sourceX < CGFloat(width - 1),
                              sourceY < CGFloat(height - 1) else { continue }
                        let left = Int(sourceX)
                        let top = Int(sourceY)
                        let dx = sourceX - CGFloat(left)
                        let dy = sourceY - CGFloat(top)
                        let topOffset = (top * width + left) * 4
                        let bottomOffset = topOffset + width * 4
                        let destinationOffset = (row * side + column) * 4
                        for channel in 0..<4 {
                            let upper = CGFloat(source[topOffset + channel]) * (1 - dx)
                                + CGFloat(source[topOffset + channel + 4]) * dx
                            let lower = CGFloat(source[bottomOffset + channel]) * (1 - dx)
                                + CGFloat(source[bottomOffset + channel + 4]) * dx
                            destination[destinationOffset + channel] = UInt8(clamping: Int((upper * (1 - dy) + lower * dy).rounded()))
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: output as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: Self.colorSpace, bitmapInfo: Self.bitmapInfo,
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        let halfSide = CGFloat(extent) / scale
        let frame = CGRect(x: warp.attachment.x - halfSide, y: warp.attachment.y - halfSide,
                           width: halfSide * 2, height: halfSide * 2)
        return (image, frame)
    }
}
