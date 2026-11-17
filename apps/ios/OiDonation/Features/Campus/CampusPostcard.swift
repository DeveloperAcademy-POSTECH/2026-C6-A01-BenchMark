//
//  CampusPostcard.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import SwiftUI
import CryptoKit
import ImageIO

/// Published snapshots remain approved pixels. New postcard snapshots are shown
/// directly; older stories use their approved photo or cucumber portrait.
struct CampusPostcard: View {
    let story: CampusStory
    let store: CampusStoryStore
    /// 카드 이미지 저장·공유 button under the postcard; hidden for now (#399).
    var showsExport = false
    @State private var showingBack = false
    @State private var snapshot: UIImage?
    @State private var backSnapshot: UIImage?
    @State private var showingExport = false
    @State private var backgroundStyle: OiPostcardBackgroundStyle?
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var localRecord: (owner: UUID, value: OiLocalDraft)?
    @State private var colors: (UInt32, UInt32) = (0xE8EECF, 0xD5DBC6)
    @Environment(\.campusCucumberPortraitLoader) private var loadImage
    @State private var frontFailed = false
    @State private var backFailed = false
    private var failed: Bool { frontFailed || backFailed }
    @State private var retry = 0
    private func loadPostcardImage(_ path: String) async throws -> UIImage {
        if let remote { return try await remote.postcardImage(path) }
        guard let loadImage else { throw OiServiceError.unavailable }
        return try await loadImage(path)
    }
    /// True once the approved front has been read (or found to be a legacy card) for the current story.
    @State private var artworkResolved = false
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
        // A legacy back must wait for the approved front's author display rule.
        if story.cardArtworkPath != nil && !artworkResolved { return "익명" }
        let publicProfile = remote?.profiles.first { $0.id == story.authorID }
        let publicAcademic = OiPostcardAuthor.academic(department: publicProfile?.department,
                                                        year: publicProfile?.admissionYear)
        let donor = story.donor.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = donor.isEmpty || donor == "작성자 정보 확인 중" ? "익명" : donor
        return OiPostcardAuthor.text(mode: (design?.postcardBackground ?? backgroundStyle)?.authorMode,
            name: name, academic: design?.postcardAcademicAuthor ?? publicAcademic)
    }
    var body: some View {
        VStack(spacing: 12) {
            OiFlippablePostcard(showingBack: $showingBack) {
                if let record = localDraft, let customization = record.customization {
                    OiDraftCardPreview(draft: record.draft, customization: customization,
                        donorName: remote?.profile?.publicName ?? "").frame(width: 362, height: 502)
                } else if let snapshot {
                    Image(uiImage: snapshot).resizable().frame(width: 362, height: 502)
                } else if story.cardArtworkPath != nil && !artworkResolved && !frontFailed {
                    // Never preview a story photo that the approved front may not use (#326).
                    OiPostcardFront(date: OiPostcardDate.string(from: story.date)) {
                        ZStack { Color(oiRGB: 0x77835C); ProgressView().tint(.white) }
                    }
                    .accessibilityLabel("엽서를 불러오는 중")
                } else {
                    OiPostcardFront(date: OiPostcardDate.string(from: story.date)) {
                        ZStack {
                            Color(oiRGB: 0x77835C)
                            if let photo = story.remoteMediaPaths.first {
                                OiPostcardRemotePhoto(path: photo) { path in
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
                    else if backFailed { ContentUnavailableView("카드 뒷면을 불러오지 못했어요", systemImage: "photo") }
                    else { ProgressView("뒷면 불러오는 중") }
                } else {
                    OiPostcardBack(first: colors.0, second: colors.1,
                               backgroundStyle: localDraft?.customization?.card?.postcardBackground ?? backgroundStyle,
                               message: localDraft?.draft.body ?? story.body,
                               author: fallbackAuthor, tags: story.tags, scrollable: true)
                }
            }
            Text("탭하거나 옆으로 밀어서 뒤집기").font(CampusStyle.body(12)).tracking(0.24)
                .foregroundStyle(Color(oiRGB: 0x575757))
            if failed {
                Button("저장된 엽서 다시 불러오기") { retry += 1 }.font(.caption)
            }
            if showsExport, let remote, remote.account?.id == story.authorID, !remote.needsReauthentication {
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
        .onChange(of: story.cardBackArtworkPath) { _, _ in backSnapshot = nil; backFailed = false }
        .task(id: "\(story.id)/\(story.cardArtworkPath ?? "")/\(localOwner?.uuidString ?? "")") {
            snapshot = nil; localRecord = nil; backgroundStyle = nil; frontFailed = false; colors = (0xE8EECF, 0xD5DBC6)
            artworkResolved = false
            guard let path = story.cardArtworkPath, loadImage != nil || remote != nil else {
                if let remote, let owner = localOwner, let id = UUID(uuidString: story.id),
                   let record = try? await remote.localDraft(id: id, owner: owner), !Task.isCancelled {
                    localRecord = (owner, record)
                }
                return
            }
            await loadFront(path)
        }
        .task(id: retry) {
            guard retry > 0, frontFailed, let path = story.cardArtworkPath else { return }
            await loadFront(path)
        }
        .task(id: "\(story.id)/\(story.cardBackArtworkPath ?? "")/\(showingBack)/\(retry)") {
            guard (showingBack || (retry > 0 && backFailed)), backSnapshot == nil, let path = story.cardBackArtworkPath else { return }
            backFailed = false
            do {
                let back = try await loadPostcardImage(path)
                try Task.checkCancellation()
                backSnapshot = back
            } catch { if !Task.isCancelled { backFailed = true } }
        }
    }

    private func loadFront(_ path: String) async {
        frontFailed = false
        do {
            let image = try await loadPostcardImage(path)
            try Task.checkCancellation()
            guard path == story.cardArtworkPath else { return }
            if OiPostcardSnapshot.isPostcard(image) {
                colors = (OiPostcardSnapshot.color(image, x: 0.05, y: 0.10) ?? 0xE8EECF,
                          OiPostcardSnapshot.color(image, x: 0.95, y: 0.90) ?? 0xD5DBC6)
                backgroundStyle = OiPostcardBackgroundMetadata.style(for: image)
                snapshot = image
            }
            artworkResolved = true
        } catch { if !Task.isCancelled { frontFailed = true } }
    }
}

private struct OiPostcardRemotePhoto: View {
    let path: String
    let loadURL: (String) async throws -> URL
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        Group {
            if remote == nil { OiStoryMediaImage(path: path, contentMode: .fill, loadURL: loadURL) }
            else if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed { Button("사진 다시 불러오기") { retry += 1 } }
            else { ProgressView().accessibilityLabel("사진 불러오는 중") }
        }
        .task(id: "\(path)/\(retry)/\(remote?.account?.id.uuidString ?? "public")") {
            image = nil; failed = false
            do {
                guard let remote else { throw OiServiceError.unavailable }
                let value = try await remote.postcardPhotoImage(path, loadURL: loadURL)
                try Task.checkCancellation()
                image = value
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

/// Display-only cache. Operator review and exports continue to read original artwork directly.
@MainActor final class OiPostcardImageCache {
    private final class Entry {
        let image: UIImage
        let expires: Date
        init(_ image: UIImage) { self.image = image; expires = Date().addingTimeInterval(300) }
    }
    private let images = NSCache<NSString, Entry>()
    private var pending: [String: Task<UIImage, Error>] = [:]
    private var epoch = UUID()
    private let worker = Worker()

    init() { images.totalCostLimit = 16 * 1024 * 1024; images.countLimit = 2 }

    func clear() {
        epoch = UUID()
        images.removeAllObjects()
        pending.values.forEach { $0.cancel() }; pending.removeAll()
    }

    func image(_ path: String, photo: Bool = false, load: @escaping () async throws -> Data) async throws -> UIImage {
        try Task.checkCancellation()
        if let entry = images.object(forKey: path as NSString), entry.expires > Date() { return entry.image }
        let started = epoch
        if let task = pending[path] {
            let value = try await task.value
            try Task.checkCancellation()
            guard epoch == started else { throw CancellationError() }
            return value
        }
        let key = started.uuidString + "/" + path
        let task = Task { [worker] in
            let data: Data
            if let cached = await worker.read(key) { data = cached }
            else { data = try await load() }
            try Task.checkCancellation()
            let image = try await worker.decode(data, photo: photo)
            try Task.checkCancellation()
            await worker.write(data, key: key)
            OiPostcardBackgroundMetadata.remember(png: data, image: image)
            return image
        }
        pending[path] = task
        do {
            let image = try await task.value
            guard epoch == started else { throw CancellationError() }
            pending[path] = nil
            if ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue,
               let cg = image.cgImage {
                images.setObject(Entry(image), forKey: path as NSString, cost: cg.bytesPerRow * cg.height)
            }
            try Task.checkCancellation()
            return image
        } catch {
            if epoch == started { pending[path] = nil }
            throw error
        }
    }

    /// Actor execution keeps file I/O and full-resolution PNG decoding off the UI actor.
    private actor Worker {
        private var directory: URL {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("OiPostcardDisplay-v1", isDirectory: true)
        }
        private func file(_ key: String) -> URL {
            let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            return directory.appendingPathComponent(hash)
        }
        func read(_ key: String) -> Data? {
            let url = file(key)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate, Date().timeIntervalSince(date) < 300 else { return nil }
            return try? Data(contentsOf: url)
        }
        func write(_ data: Data, key: String) {
            guard !Task.isCancelled else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            var total = data.count
            for url in files.sorted(by: {
                let a = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let b = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (a ?? .distantPast) > (b ?? .distantPast)
            }) {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = values?.fileSize ?? 0
                if total + size > 64 * 1024 * 1024 || Date().timeIntervalSince(values?.contentModificationDate ?? .distantPast) > 300 {
                    try? FileManager.default.removeItem(at: url)
                } else { total += size }
            }
            try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        func decode(_ data: Data, photo: Bool) throws -> UIImage {
            if photo {
                guard data.count <= 40_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_777_216,
                      let image = UIImage(data: data) else { throw OiPhotoDataError.unreadable }
                return image.preparingForDisplay() ?? image
            }
            let cg = try OiPublishedCucumberImage.decode(data, part: .portrait)
            let image = UIImage(cgImage: cg)
            return image.preparingForDisplay() ?? image
        }
    }
}
