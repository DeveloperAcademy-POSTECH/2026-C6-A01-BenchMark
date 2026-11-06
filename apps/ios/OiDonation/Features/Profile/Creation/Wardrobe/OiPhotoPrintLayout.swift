//
//  OiPhotoPrintLayout.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/6/26.
//

import UIKit

/// Coordinates use the same square, top-left origin as persisted photo placements.
/// The editor, live atlas and saved look all clip to this one authored print area.
struct OiPhotoPrintFrame: Decodable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let radius: Double

    func rect(edge: CGFloat) -> CGRect {
        CGRect(x: x * edge, y: y * edge, width: width * edge, height: height * edge)
    }
    func path(edge: CGFloat) -> CGPath {
        CGPath(roundedRect: rect(edge: edge), cornerWidth: radius * edge, cornerHeight: radius * edge, transform: nil)
    }
    func placement(for image: UIImage) -> OiPhotoPlacement {
        let aspect = image.size.width / max(image.size.height, 1)
        return OiPhotoPlacement(x: x + width / 2, y: y + height / 2,
            width: min(1.5, max(width, height * aspect)))
    }
}

struct OiPhotoPrintLayout: Decodable {
    let front: OiPhotoPrintFrame
    let back: OiPhotoPrintFrame

    subscript(_ side: OiPhotoSide) -> OiPhotoPrintFrame { side == .front ? front : back }

    private static let layouts: [String: OiPhotoPrintLayout] = {
        guard let url = Bundle.main.url(forResource: "photo-print-frames", withExtension: "json", subdirectory: "WardrobePhotoUV")
                ?? Bundle.main.url(forResource: "photo-print-frames", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layouts = try? JSONDecoder().decode([String: OiPhotoPrintLayout].self, from: data) else { return [:] }
        return layouts
    }()

    static func load(resource: String) throws -> OiPhotoPrintLayout {
        guard let layout = layouts[resource] else { throw OiPhotoDataError.unreadable }
        return layout
    }
}
