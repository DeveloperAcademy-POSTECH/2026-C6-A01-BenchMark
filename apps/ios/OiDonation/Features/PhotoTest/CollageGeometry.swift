// Created by 이돈혁

import Foundation
import CoreGraphics

struct CollageArrangement {
    let aspectRatio: CGFloat
    let frames: [CGRect]

    static func automatic(aspectRatios: [CGFloat]) -> CollageArrangement? {
        guard (1...4).contains(aspectRatios.count),
              aspectRatios.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return candidates(aspectRatios[...]).min { score($0) < score($1) }
    }

    private static func score(_ arrangement: CollageArrangement) -> CGFloat {
        let smallestArea = arrangement.frames.map { $0.width * $0.height }.min() ?? 1
        // Prefer a compact rectangle without making one photo disproportionately small.
        return abs(log(arrangement.aspectRatio)) + 0.15 * log(1 / smallestArea)
    }

    private static func candidates(_ ratios: ArraySlice<CGFloat>) -> [CollageArrangement] {
        if let ratio = ratios.first, ratios.count == 1 {
            return [CollageArrangement(aspectRatio: ratio, frames: [CGRect(x: 0, y: 0, width: 1, height: 1)])]
        }
        var result: [CollageArrangement] = []
        for split in 1..<ratios.count {
            for first in candidates(ratios.prefix(split)) {
                for second in candidates(ratios.dropFirst(split)) {
                    let horizontalRatio = first.aspectRatio + second.aspectRatio
                    let width = first.aspectRatio / horizontalRatio
                    result.append(CollageArrangement(aspectRatio: horizontalRatio, frames:
                        remap(first.frames, into: CGRect(x: 0, y: 0, width: width, height: 1)) +
                        remap(second.frames, into: CGRect(x: width, y: 0, width: 1 - width, height: 1))))
                    let verticalRatio = 1 / (1 / first.aspectRatio + 1 / second.aspectRatio)
                    let height = verticalRatio / first.aspectRatio
                    result.append(CollageArrangement(aspectRatio: verticalRatio, frames:
                        remap(first.frames, into: CGRect(x: 0, y: 0, width: 1, height: height)) +
                        remap(second.frames, into: CGRect(x: 0, y: height, width: 1, height: 1 - height))))
                }
            }
        }
        return result
    }

    private static func remap(_ frames: [CGRect], into container: CGRect) -> [CGRect] {
        frames.map {
            CGRect(x: container.minX + $0.minX * container.width,
                   y: container.minY + $0.minY * container.height,
                   width: $0.width * container.width, height: $0.height * container.height)
        }
    }
}

enum CollageTemplate: String, CaseIterable, Identifiable {
    case twoColumns, twoRows, threeColumns, threeRows, feature, grid
    var id: Self { self }
    var title: String {
        switch self {
        case .twoColumns: "세로 2칸"
        case .twoRows: "가로 2칸"
        case .threeColumns: "세로 3칸"
        case .threeRows: "가로 3칸"
        case .feature: "큰 사진 + 2칸"
        case .grid: "4칸"
        }
    }
    var frames: [CGRect] {
        switch self {
        case .twoColumns: return grid(columns: 2, rows: 1)
        case .twoRows: return grid(columns: 1, rows: 2)
        case .threeColumns: return grid(columns: 3, rows: 1)
        case .threeRows: return grid(columns: 1, rows: 3)
        case .feature:
            return [CGRect(x: 0, y: 0, width: 0.6, height: 1),
                    CGRect(x: 0.6, y: 0, width: 0.4, height: 0.5),
                    CGRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5)]
        case .grid: return grid(columns: 2, rows: 2)
        }
    }
    private func grid(columns: Int, rows: Int) -> [CGRect] {
        (0..<(columns * rows)).map {
            CGRect(x: CGFloat($0 % columns) / CGFloat(columns), y: CGFloat($0 / columns) / CGFloat(rows),
                   width: 1 / CGFloat(columns), height: 1 / CGFloat(rows))
        }
    }
}

struct CollageCrop: Equatable {
    var zoom: CGFloat = 1
    // Offset is expressed in cell widths/heights, independent of preview/export resolution.
    var x: CGFloat = 0
    var y: CGFloat = 0

    func imageFrame(imageSize: CGSize, cellSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, cellSize.width > 0, cellSize.height > 0 else { return .zero }
        let scale = max(cellSize.width / imageSize.width, cellSize.height / imageSize.height) * min(4, max(1, zoom))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let maxX = max(0, (size.width - cellSize.width) / 2)
        let maxY = max(0, (size.height - cellSize.height) / 2)
        return CGRect(x: (cellSize.width - size.width) / 2 + min(maxX, max(-maxX, x * cellSize.width)),
                      y: (cellSize.height - size.height) / 2 + min(maxY, max(-maxY, y * cellSize.height)),
                      width: size.width, height: size.height)
    }

    func clamped(imageSize: CGSize, cellSize: CGSize) -> CollageCrop {
        guard cellSize.width > 0, cellSize.height > 0 else { return CollageCrop() }
        let frame = imageFrame(imageSize: imageSize, cellSize: cellSize)
        return CollageCrop(zoom: min(4, max(1, zoom)),
                           x: (frame.midX - cellSize.width / 2) / cellSize.width,
                           y: (frame.midY - cellSize.height / 2) / cellSize.height)
    }
}
