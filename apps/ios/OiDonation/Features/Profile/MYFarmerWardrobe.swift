//
//  MYFarmerWardrobe.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/5/26.
//

import SwiftUI

enum MYFarmerSlot: String, CaseIterable, Identifiable, Codable {
    case pose, top, bottom, shoes, hat, set, accessory, special

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pose: "포즈"
        case .top: "상의"
        case .bottom: "하의"
        case .shoes: "신발"
        case .hat: "모자"
        case .set: "세트"
        case .accessory: "악세서리"
        case .special: "스페셜"
        }
    }
    var isAvailable: Bool { ![.pose, .hat, .special].contains(self) }
}

/// Coordinates and crop matrices come from the original Figma image layers.
struct MYFarmerImageLayer: Decodable {
    let asset: String
    let width: Double
    let height: Double
    let matrix: [[Double]]
    let crop: [[Double]]
    let mode: String
    let clips: [[Double]]?
}

struct MYFarmerCanvas: Decodable {
    let width: Double
    let height: Double
    let layers: [MYFarmerImageLayer]
}

struct MYFarmerWardrobeItem: Decodable, Identifiable {
    let id: String
    let name: String
    let character: String
    let slot: MYFarmerSlot
    let thumbnail: MYFarmerCanvas
    let wearables: [MYFarmerCanvas]
}

struct MYFarmerWardrobe: Decodable {
    let bodies: [String: MYFarmerCanvas]
    let items: [MYFarmerWardrobeItem]

    static let loaded: Result<MYFarmerWardrobe, Error> = Result {
        guard let url = Bundle.main.url(forResource: "FarmerWardrobe", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let wardrobe = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard Set(wardrobe.items.map(\.id)).count == wardrobe.items.count,
              wardrobe.bodies["kyu"] != nil, wardrobe.bodies["cumber"] != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return wardrobe
    }

    func items(character: String, slot: MYFarmerSlot) -> [MYFarmerWardrobeItem] {
        items.filter { $0.character == character && $0.slot == slot && !$0.wearables.isEmpty }
    }

    func item(_ id: String?) -> MYFarmerWardrobeItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    func validates(_ outfit: OiFarmerOutfit) -> Bool {
        guard outfit.version == 1, bodies[outfit.character] != nil else { return false }
        return outfit.slots.allSatisfy { slot, id in
            if slot == "set", ["legacy-classic", "legacy-casual"].contains(id) { return outfit.character == "kyu" }
            guard let item = item(id), !item.wearables.isEmpty else { return false }
            return item.character == outfit.character && item.slot.rawValue == slot
        }
    }
}

extension OiFarmerOutfit {
    static func legacy(_ appearance: MYFarmerAppearance) -> Self {
        Self(character: "kyu", slots: ["set": appearance == .classic ? "legacy-classic" : "legacy-casual"])
    }

    func selecting(_ item: MYFarmerWardrobeItem) -> Self {
        var next = character == item.character ? slots : [:]
        if item.slot == .set {
            next.removeValue(forKey: "top")
            next.removeValue(forKey: "bottom")
            next["set"] = item.id
        } else {
            if item.slot == .top || item.slot == .bottom || next["set"]?.hasPrefix("legacy-") == true {
                next.removeValue(forKey: "set")
            }
            next[item.slot.rawValue] = item.id
        }
        return Self(character: item.character, slots: next)
    }
}

struct MYFarmerLayeredArtwork: View {
    let outfit: OiFarmerOutfit
    let wardrobe: MYFarmerWardrobe

    var body: some View {
        Group {
            if outfit.slots["set"] == "legacy-classic" {
                MYFarmerPresetArtwork(appearance: .classic)
            } else if outfit.slots["set"] == "legacy-casual" {
                MYFarmerPresetArtwork(appearance: .casual)
            } else if let body = wardrobe.bodies[outfit.character] {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / body.width, geometry.size.height / body.height)
                    ZStack(alignment: .topLeading) {
                        MYFarmerCanvasArtwork(canvas: body)
                        ForEach([MYFarmerSlot.shoes, .bottom, .top, .set, .hat, .accessory]) { slot in
                            if let item = wardrobe.item(outfit.slots[slot.rawValue]) {
                                ForEach(Array(item.wearables.enumerated()), id: \.offset) { _, canvas in
                                    MYFarmerCanvasArtwork(canvas: canvas)
                                        .scaleEffect(x: body.width / canvas.width, y: body.height / canvas.height, anchor: .topLeading)
                                }
                            }
                        }
                    }
                    .frame(width: body.width, height: body.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: (geometry.size.width - body.width * scale) / 2,
                            y: (geometry.size.height - body.height * scale) / 2)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct MYFarmerCanvasArtwork: View {
    let canvas: MYFarmerCanvas

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(canvas.layers.enumerated()), id: \.offset) { _, layer in
                if let clips = layer.clips, !clips.isEmpty {
                    Color.clear.frame(width: canvas.width, height: canvas.height)
                        .overlay(alignment: .topLeading) {
                            MYFarmerImageArtwork(layer: layer).transformEffect(Self.transform(layer.matrix))
                        }
                        .clipShape(MYFarmerClip(clips: clips))
                } else {
                    MYFarmerImageArtwork(layer: layer).transformEffect(Self.transform(layer.matrix))
                }
            }
        }.frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    static func transform(_ matrix: [[Double]]) -> CGAffineTransform {
        guard matrix.count == 2, matrix.allSatisfy({ $0.count == 3 }) else { return .identity }
        return CGAffineTransform(a: matrix[0][0], b: matrix[1][0], c: matrix[0][1], d: matrix[1][1],
                                 tx: matrix[0][2], ty: matrix[1][2])
    }
}

private struct MYFarmerClip: Shape {
    let clips: [[Double]]

    func path(in rect: CGRect) -> Path {
        let bounds = clips.reduce(rect) { result, clip in
            guard clip.count == 4 else { return result }
            return result.intersection(CGRect(x: clip[0], y: clip[1], width: clip[2], height: clip[3]))
        }
        return Path(bounds)
    }
}

private struct MYFarmerImageArtwork: View {
    let layer: MYFarmerImageLayer

    var body: some View {
        Group {
            if layer.mode == "CROP" {
                let normalized = MYFarmerCanvasArtwork.transform(layer.crop).inverted()
                let transform = CGAffineTransform(a: normalized.a, b: normalized.b * layer.height / layer.width,
                    c: normalized.c * layer.width / layer.height, d: normalized.d,
                    tx: normalized.tx * layer.width, ty: normalized.ty * layer.height)
                Image(layer.asset).resizable().frame(width: layer.width, height: layer.height)
                    .transformEffect(transform)
            } else {
                Image(layer.asset).resizable()
                    .aspectRatio(contentMode: layer.mode == "FIT" ? .fit : .fill)
                    .frame(width: layer.width, height: layer.height)
            }
        }.frame(width: layer.width, height: layer.height, alignment: .topLeading).clipped()
    }
}
