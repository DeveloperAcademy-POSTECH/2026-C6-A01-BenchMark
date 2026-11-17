//
//  ScratchPostcardLoaderChecks.swift
//  OiDonationClip
//
//  Created by Codex on 11/15/26.
//

import SwiftUI
import UIKit

// UI-only collaborators are inert: these checks execute the production loader, not its views.
struct ScratchPostcardView: View {
    let postcard: ScratchPostcard
    let validateCollection: () async throws -> Bool
    let onBlock: () -> Void
    let onRetryFaces: () -> Void
    var body: some View { EmptyView() }
}
enum CheckLineHeight { case exact(points: CGFloat) }
extension Text { func lineHeight(_ value: CheckLineHeight) -> Self { self } }

private struct FixtureRepository: StoryRepository {
    let details: PublicPostcardDetails
    func fetchPublicStory(storyID: String) async throws -> Story? {
        Story(storyID: storyID, donorID: UUID(), donorDisplayName: "가상 작성자", title: "테스트",
              content: "가상 자료", publishedAt: Date(), location: .init(locationID: "pond", displayName: "연못"),
              tags: [], cucumberID: storyID, cucumberName: "테스트오이")
    }
    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        StoryCard(cardID: storyID, storyID: storyID, imageURL: details.frontURL)
    }
    func fetchNFCPostcardStoryID(tag: String) async throws -> String? { UUID().uuidString }
    func fetchPublicPostcardDetails(storyID: String) async throws -> PublicPostcardDetails? { details }
}

@main struct ScratchPostcardLoaderChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func image(_ color: UIColor, size: CGSize) -> UIImage {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }
        }
        func file(_ name: String, _ data: Data) throws -> URL {
            let url = directory.appendingPathComponent(name); try data.write(to: url); return url
        }
        let front = try file("front.png", image(.red, size: CGSize(width: 362, height: 502)).pngData()!)
        let back = try file("back.png", image(.blue, size: CGSize(width: 362, height: 502)).pngData()!)
        let jpeg = image(.green, size: CGSize(width: 888, height: 1308)).jpegData(compressionQuality: 0.8)!
        let cover = try file("cover.jpg", jpeg)
        let loader = ScratchPostcardLoader()
        func load(_ coverURL: URL?, type: StoryCard.CoverType = .jpeg, backURL: URL? = nil) async -> ScratchPostcard? {
            let details = PublicPostcardDetails(frontURL: front, backURL: backURL ?? back, coverPhotoURL: nil,
                donorLine: nil, coverURL: coverURL, coverType: type)
            await loader.load(tag: "fixture", repository: FixtureRepository(details: details))
            if case .loaded(let value) = loader.state { return value }
            return nil
        }
        guard let first = await load(cover), let clean = first.coverPhoto?.cgImage else { fatalError("JPEG cover did not load") }
        precondition(clean.width == 888 && clean.height == 1308, "The JPEG window must take priority over the front crop")
        precondition(first.back != nil && first.front != nil)
        print("PASS: App Clip loads the actual 888×1308 JPEG cover and both PNG sides")
        let png = try file("legacy-cover.png", image(.green, size: CGSize(width: 888, height: 1308)).pngData()!)
        let legacy = await load(png, type: .png)
        precondition(legacy?.coverPhoto?.cgImage?.width == 888)
        var oversized = jpeg; oversized.append(Data(count: 2 * 1024 * 1024 + 1 - jpeg.count))
        let large = try file("oversized.jpg", oversized)
        let corrupt = try file("broken.jpg", Data("broken".utf8))
        let missing = directory.appendingPathComponent("missing.jpg")
        for optionalCover in [nil, missing, corrupt, large, png] as [URL?] {
            guard let value = await load(optionalCover), let crop = value.coverPhoto?.cgImage else { fatalError("Front fallback did not load") }
            precondition(crop.width == 296 && crop.height == 436, "Unavailable/invalid JPEG must use the approved front window")
        }
        print("PASS: legacy PNG plus missing, corrupt, oversized and mismatched JPEG fallbacks")
        guard let partial = await load(cover, backURL: missing) else {
            fatalError("A failed back must keep the visible postcard")
        }
        precondition(partial.backFailed && !partial.frontFailed && partial.back == nil)
        let retry = FixtureRepository(details: PublicPostcardDetails(frontURL: front, backURL: back,
            coverPhotoURL: nil, donorLine: nil, coverURL: cover, coverType: .jpeg))
        await loader.retryFaces(repository: retry, usesTag: false)
        guard case .loaded(let repaired) = loader.state else { fatalError("Retry removed the visible postcard") }
        precondition(!repaired.hasFailedFaces && repaired.back != nil
            && repaired.front === partial.front && repaired.coverPhoto === partial.coverPhoto)
        print("PASS: mandatory back failure keeps the postcard and retries only the failed face")
    }
}
