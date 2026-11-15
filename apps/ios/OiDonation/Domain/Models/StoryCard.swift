//
//  StoryCard.swift
//  OiDonation
//
//  Created by jiwon hong on 10/28/26.
//

import Foundation

struct StoryCard: Identifiable, Sendable {
    var id: String { cardID }
    let cardID: String
    let storyID: String
    let imageURL: URL?
    var backImageURL: URL? = nil
    var frontPreviewURL: URL? = nil
    var backPreviewURL: URL? = nil

    enum Part: String, CaseIterable, Sendable {
        case front, back, frontPreview = "front-preview", backPreview = "back-preview", cover

        static let duplex: [Self] = [.front, .back, .frontPreview, .backPreview]
        static func parts(format: Int) -> [Self] {
            format == 3 ? duplex + [.cover] : (format == 2 ? duplex : [.front])
        }
    }

    enum CoverType: String, Codable, Sendable {
        case png, jpeg

        nonisolated var fileExtension: String { self == .jpeg ? "jpg" : "png" }
        nonisolated var contentType: String { self == .jpeg ? "image/jpeg" : "image/png" }
        nonisolated var typeIdentifier: String { self == .jpeg ? "public.jpeg" : "public.png" }
        nonisolated var maximumBytes: Int { (self == .jpeg ? 2 : 8) * 1024 * 1024 }

        // Missing metadata belongs to the original format-3 PNG contract.
        static func resolve(_ raw: String?) -> Self? {
            guard let raw else { return .png }
            return Self(rawValue: raw)
        }
    }

    static func artworkPath(owner: UUID, story: UUID, snapshot: UUID, part: Part, coverType: CoverType = .png) -> String {
        if part == .front { return artworkPath(owner: owner, story: story, snapshot: snapshot) }
        return "\(owner.uuidString.lowercased())/\(story.uuidString.lowercased())/card/\(snapshot.uuidString.lowercased())/\(part.rawValue).\(part == .cover ? coverType.fileExtension : "png")"
    }

    static func artworkPath(owner: UUID, story: UUID, snapshot: UUID) -> String {
        "\(owner.uuidString.lowercased())/\(story.uuidString.lowercased())/card/\(snapshot.uuidString.lowercased()).png"
    }


}
