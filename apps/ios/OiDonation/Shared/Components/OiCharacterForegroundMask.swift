//
//  OiCharacterForegroundMask.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import CoreGraphics
import CoreImage
import ImageIO
import Vision

/// Native foreground segmentation for isolated character portraits, never postcard photographs.
enum OiCharacterForegroundMask {
    enum Failure: Error { case unreadable, noForeground }

    nonisolated static func image(_ source: CGImage, orientation: CGImagePropertyOrientation = .up,
                                  context: CIContext) throws -> CGImage {
        try Task.checkCancellation()
        let handler = VNImageRequestHandler(cgImage: source, orientation: orientation)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        try Task.checkCancellation()
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw Failure.noForeground }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances,
            from: handler, croppedToInstancesExtent: false)
        try Task.checkCancellation()
        let masked = CIImage(cvPixelBuffer: buffer)
        guard let image = context.createCGImage(masked, from: masked.extent) else { throw Failure.unreadable }
        return image
    }

    /// Empty outer padding does not prove that the figure itself has been cut out.
    nonisolated static func hasTransparentBackground(_ image: CGImage) -> Bool {
        guard let pixels = alphaPixels(image) else { return false }
        let bounds = pixels.bounds
        var clear = 0
        for y in Int(bounds.minY)..<Int(bounds.maxY) {
            for x in Int(bounds.minX)..<Int(bounds.maxX) where pixels.alpha[y * image.width + x] < 8 { clear += 1 }
        }
        return clear > Int(bounds.width * bounds.height) / 100
    }

    nonisolated static func opaqueBounds(_ image: CGImage) -> CGRect? { alphaPixels(image)?.bounds }

    nonisolated private static func alphaPixels(_ image: CGImage) -> (alpha: [UInt8], bounds: CGRect)? {
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (alpha, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
