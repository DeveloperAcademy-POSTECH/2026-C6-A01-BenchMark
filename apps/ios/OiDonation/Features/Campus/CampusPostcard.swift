//
//  CampusPostcard.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import SwiftUI

/// Published snapshots remain approved pixels. New postcard snapshots are shown
/// directly; older stories use their approved photo or cucumber portrait.
struct CampusPostcard: View {
    let story: CampusStory
    let store: CampusStoryStore
    @State private var showingBack = false
    @State private var snapshot: UIImage?
    @State private var backSnapshot: UIImage?
    @State private var showingExport = false
    @State private var backgroundStyle: OiPostcardBackgroundStyle?
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var localRecord: (owner: UUID, value: OiLocalDraft)?
    @State private var colors: (UInt32, UInt32) = (0xE8EECF, 0xD5DBC6)
    @Environment(\.campusCucumberPortraitLoader) private var loadImage
    @State private var failed = false
    @State private var retry = 0
    private var localOwner: UUID? {
        guard story.cardArtworkPath == nil, let remote, !remote.needsReauthentication,
              let owner = remote.account?.id, owner == story.authorID else { return nil }
        return owner
    }
    private var localDraft: OiLocalDraft? {
        guard let localRecord, localRecord.owner == localOwner,
              localRecord.value.id == UUID(uuidString: story.id) else { return nil }
        return localRecord.value
    }
    private var fallbackAuthor: String {
        let design = localDraft?.customization?.card
        return OiPostcardAuthor.text(mode: (design?.postcardBackground ?? backgroundStyle)?.authorMode,
            name: story.donor, academic: design?.postcardAcademicAuthor ?? "")
    }
    var body: some View {
        VStack(spacing: 10) {
            OiFlippablePostcard(showingBack: $showingBack) {
                if let record = localDraft, let customization = record.customization {
                    OiDraftCardPreview(draft: record.draft, customization: customization,
                        donorName: remote?.profile?.publicName ?? "").frame(width: 362, height: 502)
                } else if let snapshot {
                    Image(uiImage: snapshot).resizable().frame(width: 362, height: 502)
                } else {
                    OiPostcardFront(date: OiPostcardDate.string(from: story.date)) {
                        ZStack {
                            Color(oiRGB: 0x77835C)
                            if let photo = story.remoteMediaPaths.first {
                                OiStoryMediaImage(path: photo, contentMode: .fill) { path in
                                    guard let resolver = store.mediaURL else { throw OiServiceError.unavailable }
                                    return try await resolver(path)
                                }
                            } else { CampusCucumberPortrait(story: story) }
                        }
                    }
                }
            } back: {
                if story.cardBackArtworkPath != nil {
                    if let backSnapshot { Image(uiImage: backSnapshot).resizable().frame(width: 362, height: 502) }
                    else { ContentUnavailableView("카드 뒷면을 불러오지 못했어요", systemImage: "photo") }
                } else {
                    OiPostcardBack(first: colors.0, second: colors.1,
                               backgroundStyle: localDraft?.customization?.card?.postcardBackground ?? backgroundStyle,
                               message: localDraft?.draft.body ?? story.body,
                               author: fallbackAuthor, scrollable: true)
                }
            }
            Text("탭하거나 옆으로 밀어서 뒤집기").font(CampusStyle.body(12)).foregroundStyle(.secondary)
            if failed {
                Button("저장된 엽서 다시 불러오기") { retry += 1 }.font(.caption)
            }
            if let remote, remote.account?.id == story.authorID, !remote.needsReauthentication {
                Button("카드 이미지 저장·공유", systemImage: "square.and.arrow.up") { showingExport = true }
                    .accessibilityIdentifier("oi.card.export.owner")
            }
        }
        .sheet(isPresented: $showingExport) {
            OiCardExportSheet {
                guard let remote, let owner = remote.account?.id, owner == story.authorID,
                      !remote.needsReauthentication else { throw OiServiceError.accountChanged }
                if let record = localDraft, let customization = record.customization {
                    return try OiCardExportImages(OiDraftCardPreview(draft: record.draft, customization: customization,
                        donorName: story.donor).publication(colorScheme: .light))
                }
                guard let path = story.cardArtworkPath, let loadImage else { throw OiCardExportError.imageUnavailable }
                let front = try await loadImage(path)
                let back: UIImage?
                if let path = story.cardBackArtworkPath { back = try await loadImage(path) }
                else { back = nil }
                try Task.checkCancellation()
                guard remote.account?.id == owner, !remote.needsReauthentication else { throw OiServiceError.accountChanged }
                return OiCardExportImages(front: front, back: back)
            }
        }
        .id(story.id)
        .task(id: "\(story.id)/\(story.cardArtworkPath ?? "")/\(story.cardBackArtworkPath ?? "")/\(localOwner?.uuidString ?? "")/\(retry)") {
            snapshot = nil; backSnapshot = nil; localRecord = nil; backgroundStyle = nil; failed = false; colors = (0xE8EECF, 0xD5DBC6)
            guard let path = story.cardArtworkPath, let loadImage else {
                if let remote, let owner = localOwner, let id = UUID(uuidString: story.id),
                   let record = try? await remote.localDraft(id: id, owner: owner), !Task.isCancelled {
                    localRecord = (owner, record)
                }
                return
            }
            do {
                let image = try await loadImage(path)
                try Task.checkCancellation()
                if OiPostcardSnapshot.isPostcard(image) {
                    colors = (OiPostcardSnapshot.color(image, x: 0.05, y: 0.10) ?? 0xE8EECF,
                              OiPostcardSnapshot.color(image, x: 0.95, y: 0.90) ?? 0xD5DBC6)
                    backgroundStyle = OiPostcardBackgroundMetadata.style(for: image)
                    snapshot = image
                }
                if let backPath = story.cardBackArtworkPath {
                    let back = try await loadImage(backPath)
                    try Task.checkCancellation()
                    backSnapshot = back
                }
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

/// Read a few approved snapshot pixels once, without changing the stored image.
enum OiPostcardSnapshot {
    static func isPostcard(_ image: UIImage) -> Bool {
        // Figma's first left perforation is centered at y=31; legacy rounded
        // cards are opaque here. Check both edges to avoid classifying a photo.
        pixel(image, x: 0.003, y: 31.0 / 502).3 < 30 && pixel(image, x: 0.997, y: 31.0 / 502).3 < 30
    }
    static func color(_ image: UIImage, x: Double, y: Double) -> UInt32? {
        let p = pixel(image, x: x, y: y)
        guard p.3 > 240 else { return nil }
        return UInt32(p.0) << 16 | UInt32(p.1) << 8 | UInt32(p.2)
    }
    private static func pixel(_ image: UIImage, x: Double, y: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        guard let cg = image.cgImage else { return (0, 0, 0, 255) }
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.translateBy(x: -CGFloat(x) * CGFloat(cg.width), y: -CGFloat(1 - y) * CGFloat(cg.height))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return (rgba[0], rgba[1], rgba[2], rgba[3])
    }
}
