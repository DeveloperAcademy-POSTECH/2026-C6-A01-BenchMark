//
//  compare-my.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/16/26.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Standalone MY ver.4 verification artifact; never linked into the application.
// Usage: swift compare-my.swift reference.png actual.png output-directory

enum ComparisonError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]
}

struct Bounds: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

func image(from raster: Raster) throws -> CGImage {
    guard let provider = CGDataProvider(data: Data(raster.pixels) as CFData),
          let result = CGImage(width: raster.width, height: raster.height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: raster.width * 4,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric) else {
        throw ComparisonError.invalid("Cannot construct an sRGB RGBA image")
    }
    return result
}

func draw(_ source: CGImage) throws -> Raster {
    var result = Raster(width: source.width, height: source.height,
        pixels: [UInt8](repeating: 255, count: source.width * source.height * 4))
    try result.pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: source.width * 4, space: colorSpace,
            bitmapInfo: bitmapInfo) else {
            throw ComparisonError.invalid("Cannot create a normalization context")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        context.interpolationQuality = .none
        context.setRenderingIntent(.relativeColorimetric)
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    }
    return result
}

// Calibrate row order against a CGImage with a known first scanline. Region bounds
// and output buffers consequently use source-image top-left coordinates, even if
// the platform's bitmap drawing convention changes.
func drawingFlipsRows() throws -> Bool {
    let probe = Raster(width: 1, height: 2, pixels: [255, 0, 0, 255, 0, 0, 255, 255])
    let rendered = try draw(image(from: probe))
    if Array(rendered.pixels.prefix(4)) == [255, 0, 0, 255] { return false }
    if Array(rendered.pixels.prefix(4)) == [0, 0, 255, 255] { return true }
    throw ComparisonError.invalid("Unexpected orientation calibration result")
}

func load(_ url: URL, flipRows: Bool) throws -> Raster {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let decoded = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: true] as CFDictionary) else {
        throw ComparisonError.invalid("Cannot decode \(url.path)")
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    guard orientation == 1 else {
        throw ComparisonError.invalid("Input orientation must be upright (1), got \(orientation): \(url.path)")
    }
    var raster = try draw(decoded)
    if flipRows {
        let original = raster.pixels
        let stride = raster.width * 4
        for row in 0..<raster.height {
            let first = row * stride
            let sourceFirst = (raster.height - 1 - row) * stride
            raster.pixels.replaceSubrange(first..<(first + stride),
                with: original[sourceFirst..<(sourceFirst + stride)])
        }
    }
    return raster
}

func save(_ raster: Raster, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ComparisonError.invalid("Cannot create \(url.path)")
    }
    CGImageDestinationAddImage(destination, try image(from: raster), nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ComparisonError.invalid("Cannot write \(url.path)")
    }
}

struct Metrics: Codable {
    let bounds: Bounds
    let pixels: Int
    let meanAbsoluteRGBError: Double
    let rootMeanSquareRGBError: Double
    let maximumRGBError: Int
    let pixelsAbove10RGB: Int
    let ratioAbove10RGB: Double
}

func metrics(_ reference: Raster, _ actual: Raster, bounds: Bounds) throws -> Metrics {
    guard bounds.x >= 0, bounds.y >= 0, bounds.width > 0, bounds.height > 0,
          bounds.x + bounds.width <= reference.width, bounds.y + bounds.height <= reference.height else {
        throw ComparisonError.invalid("A comparison region exceeds the image bounds")
    }
    var absolute = 0.0
    var squares = 0.0
    var maximum = 0
    var changed = 0
    for y in bounds.y..<(bounds.y + bounds.height) {
        for x in bounds.x..<(bounds.x + bounds.width) {
            let offset = (y * reference.width + x) * 4
            var pixelMaximum = 0
            for channel in 0..<3 {
                let delta = abs(Int(reference.pixels[offset + channel]) - Int(actual.pixels[offset + channel]))
                absolute += Double(delta)
                squares += Double(delta * delta)
                maximum = max(maximum, delta)
                pixelMaximum = max(pixelMaximum, delta)
            }
            if pixelMaximum > 10 { changed += 1 }
        }
    }
    let pixels = bounds.width * bounds.height
    return Metrics(bounds: bounds, pixels: pixels,
        meanAbsoluteRGBError: absolute / Double(pixels * 3),
        rootMeanSquareRGBError: sqrt(squares / Double(pixels * 3)),
        maximumRGBError: maximum, pixelsAbove10RGB: changed,
        ratioAbove10RGB: Double(changed) / Double(pixels))
}

struct Report: Codable {
    let reference: String
    let actual: String
    let width: Int
    let height: Int
    let normalization: String
    let bitmapDrawingRequiredRowFlip: Bool
    let coordinateSystem: String
    let thresholdDefinition: String
    let fullFrame: Metrics
    let regions: [String: Metrics]
    let artifacts: [String: String]
    let heatmapLegend: String
    let verdict: String
    let intentionalDifferences: [String]
}

func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else {
        throw ComparisonError.invalid("Usage: swift compare-my.swift reference.png actual.png output-directory")
    }
    let referenceURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let actualURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let output = URL(fileURLWithPath: arguments[3], isDirectory: true).standardizedFileURL
    let flipRows = try drawingFlipsRows()
    let reference = try load(referenceURL, flipRows: flipRows)
    let actual = try load(actualURL, flipRows: flipRows)
    guard reference.width == 402, reference.height == 874,
          actual.width == reference.width, actual.height == reference.height else {
        throw ComparisonError.invalid("Expected matching 402×874 PNGs; reference \(reference.width)×\(reference.height), actual \(actual.width)×\(actual.height)")
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var sideBySide = Raster(width: reference.width * 2, height: reference.height,
        pixels: [UInt8](repeating: 255, count: reference.width * 2 * reference.height * 4))
    var overlay = reference
    var heatmap = reference
    for y in 0..<reference.height {
        for x in 0..<reference.width {
            let sourceOffset = (y * reference.width + x) * 4
            let leftOffset = (y * sideBySide.width + x) * 4
            let rightOffset = (y * sideBySide.width + reference.width + x) * 4
            var delta = 0
            for channel in 0..<4 {
                sideBySide.pixels[leftOffset + channel] = reference.pixels[sourceOffset + channel]
                sideBySide.pixels[rightOffset + channel] = actual.pixels[sourceOffset + channel]
                overlay.pixels[sourceOffset + channel] = UInt8((Int(reference.pixels[sourceOffset + channel])
                    + Int(actual.pixels[sourceOffset + channel]) + 1) / 2)
                if channel < 3 {
                    delta = max(delta, abs(Int(reference.pixels[sourceOffset + channel]) - Int(actual.pixels[sourceOffset + channel])))
                }
            }
            heatmap.pixels[sourceOffset] = UInt8(min(255, delta * 4))
            heatmap.pixels[sourceOffset + 1] = UInt8(delta)
            heatmap.pixels[sourceOffset + 2] = 0
            heatmap.pixels[sourceOffset + 3] = 255
        }
    }
    let sideURL = output.appendingPathComponent("side-by-side.png")
    let overlayURL = output.appendingPathComponent("overlay-50-percent.png")
    let heatmapURL = output.appendingPathComponent("absolute-diff-heatmap.png")
    try save(sideBySide, to: sideURL)
    try save(overlay, to: overlayURL)
    try save(heatmap, to: heatmapURL)
    let regions = [
        "headerBlank": Bounds(x: 0, y: 62, width: 20, height: 175),
        "farmer": Bounds(x: 265, y: 85, width: 110, height: 208),
        "panelBlank": Bounds(x: 0, y: 570, width: 402, height: 180),
        "tabBar": Bounds(x: 20, y: 337, width: 363, height: 34)
    ]
    let report = Report(reference: referenceURL.path, actual: actualURL.path,
        width: reference.width, height: reference.height,
        normalization: "8-bit sRGB RGBA, source alpha composited onto white; no resize or alignment correction",
        bitmapDrawingRequiredRowFlip: flipRows,
        coordinateSystem: "Top-left origin in original image pixels; x rightward, y downward",
        thresholdDefinition: "A pixel differs when max(abs(R), abs(G), abs(B)) > 10 on the 0–255 scale",
        fullFrame: try metrics(reference, actual, bounds: Bounds(x: 0, y: 0, width: 402, height: 874)),
        regions: try regions.mapValues { try metrics(reference, actual, bounds: $0) },
        artifacts: ["sideBySideReferenceLeft": sideURL.path, "overlay50Percent": overlayURL.path,
            "absoluteDiffHeatmap": heatmapURL.path],
        heatmapLegend: "Per-pixel maximum absolute RGB delta d: R=min(255,4d), G=d, B=0; black is identical",
        verdict: "MEASUREMENT ONLY: full-frame metrics are not a pass/fail verdict. Inspect fixed regions and overlays, and document residual differences.",
        intentionalDifferences: [
            "Figma device status bar and home indicator are reference chrome; the app uses native system chrome.",
            "The reference capture loads Figma card assets through the isolated XCTest service fixture; production uses account data.",
            "Unavailable donation counts and pickle coins use inactive placeholders instead of the sample 8회 and 3pc.",
            "Native Liquid Glass can differ from Figma's simulated material and shadow layers.",
            "Cucumber portraits preserve aspect ratio in a consistent 43×85 slot; Figma uses per-example 43×85 and 52×88 layouts."
        ])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let json = try encoder.encode(report)
    try json.write(to: output.appendingPathComponent("metrics.json"), options: .atomic)
    FileHandle.standardOutput.write(json)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
