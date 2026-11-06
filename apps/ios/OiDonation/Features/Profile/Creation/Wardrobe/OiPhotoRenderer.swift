import UIKit
import ImageIO
import CryptoKit

struct OiPhotoImageAsset {
    let id: String
    let image: UIImage
    let data: Data
}
struct OiPhotoDraft {
    var layers: [OiPhotoLayer] = []
    var assets: [String: OiPhotoImageAsset] = [:]

    /// Keep shared sources until their last layer is removed; never touch saved artwork here.
    mutating func remove(_ id: String, on side: OiPhotoSide) -> String? {
        layers.removeAll { $0.id == id }
        let used = Set(layers.map(\.source))
        assets = assets.filter { used.contains($0.key) }
        return layers.last { $0.side == side }?.id
    }
}

enum OiPhotoRenderer {
    // Bounded to six bundled images; drafts store IDs, never duplicate these bytes.
    private static let fabrics: [OiDenim: UIImage] = Dictionary(uniqueKeysWithValues: OiDenim.allCases.compactMap { fabric in
        guard let url = Bundle.main.url(forResource: fabric.resource, withExtension: "jpg", subdirectory: "WardrobeDenim")
                ?? Bundle.main.url(forResource: fabric.resource, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return (fabric, image)
    })
    static func fabricImage(_ fabric: OiDenim?) -> UIImage? { fabric.flatMap { fabrics[$0] } }

    static func image(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw OiPhotoDataError.unreadable }
        return UIImage(cgImage: cg)
    }
    static func asset(_ data: Data) throws -> OiPhotoImageAsset { try asset(image(data)) }
    static func asset(_ image: UIImage) throws -> OiPhotoImageAsset {
        let alpha = image.cgImage?.alphaInfo
        let transparent = alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
        guard let data = transparent ? image.pngData() : image.jpegData(compressionQuality: 0.8) else { throw OiPhotoDataError.unreadable }
        guard data.count <= OiWardrobeArtwork.maximumSourceBytes else { throw OiPhotoDataError.limit }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return OiPhotoImageAsset(id: hash, image: image, data: data)
    }

    // Only photos are clipped. Garment color/fabric still covers the complete UV texture.
    static func atlas(layers: [OiPhotoLayer], assets: [String: OiPhotoImageAsset], panelSize: Int, color: UInt32, fabric: OiDenim? = nil, transparent: Bool = false, layout: OiPhotoPrintLayout) -> UIImage {
        let edge = CGFloat(panelSize)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = !transparent
        return UIGraphicsImageRenderer(size: CGSize(width: edge * 2, height: edge), format: format).image { context in
            if !transparent {
                UIColor(wardrobeRGB: color).setFill(); context.fill(CGRect(x: 0, y: 0, width: edge * 2, height: edge))
            }
            let cg = context.cgContext
            for side in OiPhotoSide.allCases {
                cg.saveGState(); cg.translateBy(x: side == .front ? 0 : edge, y: 0)
                cg.clip(to: CGRect(x: 0, y: 0, width: edge, height: edge))
                if !transparent { fabricImage(fabric)?.draw(in: CGRect(x: 0, y: 0, width: edge, height: edge)) }
                cg.addPath(layout[side].path(edge: edge)); cg.clip()
                for layer in layers where layer.side == side {
                    guard let image = assets[layer.source]?.image else { continue }
                    let p = layer.placement
                    cg.saveGState(); cg.translateBy(x: p.x * edge, y: p.y * edge)
                    cg.rotate(by: p.rotation * .pi / 180)
                    let width = p.width * edge, height = width * image.size.height / max(image.size.width, 1)
                    image.draw(in: CGRect(x: -width/2, y: -height/2, width: width, height: height))
                    cg.restoreGState()
                }
                cg.restoreGState()
            }
        }
    }
    static func load(_ design: OiPhotoDesign, sources: [String: Data]) throws -> OiPhotoDraft {
        guard design.isValid else { throw OiPhotoDataError.unreadable }
        var draft = OiPhotoDraft(layers: design.layers)
        for id in Set(design.layers.map(\.source)) {
            guard let data = sources[id], data.count <= OiWardrobeArtwork.maximumSourceBytes,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == id else { throw OiPhotoDataError.unreadable }
            draft.assets[id] = OiPhotoImageAsset(id: id, image: try image(data), data: data)
        }
        return draft
    }
}
