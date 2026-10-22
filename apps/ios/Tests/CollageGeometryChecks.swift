// Created by 이돈혁

import Foundation
import CoreGraphics

@main struct CollageGeometryChecks {
    static func main() {
        let samples: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 4 / 3, 2, 4, 10]
        var arrangements = 0
        for count in 1...4 {
            for sample in 0..<Int(pow(Double(samples.count), Double(count))) {
                var value = sample
                let ratios = (0..<count).map { _ -> CGFloat in
                    defer { value /= samples.count }
                    return samples[value % samples.count]
                }
                guard let arrangement = CollageArrangement.automatic(aspectRatios: ratios) else {
                    fatalError("Valid photos must produce an arrangement")
                }
                checkTiling(arrangement.frames)
                assert(arrangement.frames.count == count)
                for (frame, ratio) in zip(arrangement.frames, ratios) {
                    assert(abs(frame.width * arrangement.aspectRatio / frame.height - ratio) < 0.00001,
                           "Automatic layout must preserve every original aspect ratio")
                }
                arrangements += 1
            }
        }
        for ratios: [CGFloat] in [[], [0], [-1], [.infinity], [.nan], [1, 1, 1, 1, 1]] {
            assert(CollageArrangement.automatic(aspectRatios: ratios) == nil)
        }
        for template in CollageTemplate.allCases { checkTiling(template.frames) }
        for imageSize in [CGSize(width: 400, height: 1200), CGSize(width: 1200, height: 400)] {
            for zoom: CGFloat in [0, 1, 2, 4, 9] {
                for offset: CGFloat in [-10, -1, 0, 1, 10] {
                    let crop = CollageCrop(zoom: zoom, x: offset, y: -offset)
                    let cell = CGSize(width: 300, height: 200)
                    let frame = crop.imageFrame(imageSize: imageSize, cellSize: cell)
                    assert(frame.minX <= 0.0001 && frame.minY <= 0.0001)
                    assert(frame.maxX >= cell.width - 0.0001 && frame.maxY >= cell.height - 0.0001)
                    assert(abs(frame.width / frame.height - imageSize.width / imageSize.height) < 0.0001)
                    let clamped = crop.clamped(imageSize: imageSize, cellSize: cell)
                    let exported = clamped.imageFrame(imageSize: imageSize, cellSize: CGSize(width: 1200, height: 800))
                    assert(abs(exported.minX / 4 - frame.minX) < 0.0001)
                    assert(abs(exported.minY / 4 - frame.minY) < 0.0001)
                    assert((1...4).contains(clamped.zoom))
                }
            }
        }
        assert(CollageCrop().imageFrame(imageSize: .zero, cellSize: CGSize(width: 100, height: 100)) == .zero)
        print("PASS: \(arrangements) automatic arrangements preserve ratios and tile without gaps/overlap; all templates; crop bounds and preview/export scaling")
    }

    private static func checkTiling(_ frames: [CGRect]) {
        assert(abs(frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height } - 1) < 0.00001)
        for (index, frame) in frames.enumerated() {
            assert(frame.width > 0 && frame.height > 0)
            assert(frame.minX >= -0.00001 && frame.minY >= -0.00001 && frame.maxX <= 1.00001 && frame.maxY <= 1.00001)
            for other in frames.dropFirst(index + 1) {
                let overlap = frame.intersection(other)
                assert(overlap.isNull || overlap.width * overlap.height < 0.00001)
            }
        }
    }
}
