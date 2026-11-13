//
//  ScratchCoverage.swift
//  OiDonationClip
//
//  Created by jiwon hong on 11/12/26.
//

import CoreGraphics

/// Tracks how much of the scratch foil has been rubbed off, using a coarse grid in normalized card space.
///
/// Only cells whose centers fall inside `countedInset` from every edge count toward `fraction`, so the
/// perforated stamp edge does not have to be scratched precisely.
struct ScratchCoverage: Equatable {
    let columns: Int
    let rows: Int
    let countedInset: Double
    private(set) var cells: [Bool]
    private(set) var scratchedCount = 0
    let countedTotal: Int

    init(columns: Int = 24, rows: Int = 34, countedInset: Double = 0.05) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        self.countedInset = min(max(countedInset, 0), 0.45)
        cells = Array(repeating: false, count: self.columns * self.rows)
        var total = 0
        for row in 0..<self.rows {
            for column in 0..<self.columns where Self.isCounted(column, row, self.columns, self.rows, self.countedInset) {
                total += 1
            }
        }
        countedTotal = total
    }

    /// Scratched share of the counted area, from 0 to 1.
    var fraction: Double {
        countedTotal == 0 ? 0 : Double(scratchedCount) / Double(countedTotal)
    }

    /// Marks cells under an elliptical brush. `point` and `radius` are normalized to the card size.
    /// - Returns: The number of newly scratched counted cells.
    @discardableResult
    mutating func scratch(at point: CGPoint, radius: CGVector) -> Int {
        guard point.x.isFinite, point.y.isFinite, radius.dx > 0, radius.dy > 0 else { return 0 }
        let minColumn = max(Int(((point.x - radius.dx) * CGFloat(columns)).rounded(.down)), 0)
        let maxColumn = min(Int(((point.x + radius.dx) * CGFloat(columns)).rounded(.up)), columns - 1)
        let minRow = max(Int(((point.y - radius.dy) * CGFloat(rows)).rounded(.down)), 0)
        let maxRow = min(Int(((point.y + radius.dy) * CGFloat(rows)).rounded(.up)), rows - 1)
        guard minColumn <= maxColumn, minRow <= maxRow else { return 0 }

        var added = 0
        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                let index = row * columns + column
                guard !cells[index] else { continue }
                let centerX = (CGFloat(column) + 0.5) / CGFloat(columns)
                let centerY = (CGFloat(row) + 0.5) / CGFloat(rows)
                let dx = (centerX - point.x) / radius.dx
                let dy = (centerY - point.y) / radius.dy
                guard dx * dx + dy * dy <= 1 else { continue }
                cells[index] = true
                if Self.isCounted(column, row, columns, rows, countedInset) {
                    scratchedCount += 1
                    added += 1
                }
            }
        }
        return added
    }

    /// Scratches along a segment so fast swipes do not leave unscratched gaps.
    @discardableResult
    mutating func scratch(from start: CGPoint, to end: CGPoint, radius: CGVector) -> Int {
        let distance = hypot((end.x - start.x) / radius.dx, (end.y - start.y) / radius.dy)
        guard distance.isFinite else { return 0 }
        let steps = max(Int((distance * 2).rounded(.up)), 1)
        var added = 0
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            added += scratch(at: CGPoint(x: start.x + (end.x - start.x) * t,
                                         y: start.y + (end.y - start.y) * t), radius: radius)
        }
        return added
    }

    private static func isCounted(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int, _ inset: Double) -> Bool {
        let x = (Double(column) + 0.5) / Double(columns)
        let y = (Double(row) + 0.5) / Double(rows)
        return x >= inset && x <= 1 - inset && y >= inset && y <= 1 - inset
    }
}
