//
//  OiStoryListPortrait.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import Observation
import SwiftUI

extension OiStoryListPortraitSource {
    static func local(customization: OiDraftCustomization?, asset: String, serverPath: String? = nil,
                      serverSeed: OiSeedCucumberSnapshot? = nil) -> Self {
        if let seed = customization?.seedSnapshot {
            if seed.topPhotoVersion != nil, let look = customization?.seedPhotoLook { return .seedWithPhotos(seed, look) }
            return .seed(seed)
        }
        if let look = customization?.wardrobe { return .wardrobe(look) }
        if let serverSeed, serverSeed.topPhotoVersion == nil { return .seed(serverSeed) }
        if let serverPath { return .remote(serverPath) }
        // New drafts start with the same bare seed shown by STEP 3, including an untouched look.
        if asset == "OiCats" { return .seed(.init(appearance: .init(), garments: [])) }
        return .asset(asset)
    }
}

/// Only normalized pixels cross list instances; models and capture surfaces never do.
@MainActor @Observable
final class OiStoryListPortraitCache {
    static let shared = OiStoryListPortraitCache()
    private struct Entry {
        let source: OiStoryListPortraitSource
        let image: UIImage
    }
    private var entries: [Entry] = []
    private var owner: UUID?
    private var hasOwner = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(observePressure: Bool = true) {
        if observePressure {
            for name in [UIApplication.didReceiveMemoryWarningNotification,
                         UIApplication.didEnterBackgroundNotification,
                         ProcessInfo.thermalStateDidChangeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.clear() }
                })
            }
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    var count: Int { entries.count }

    func useOwner(_ owner: UUID?) {
        guard !hasOwner || self.owner != owner else { return }
        entries.removeAll()
        self.owner = owner
        hasOwner = true
    }

    func image(for source: OiStoryListPortraitSource, owner: UUID?) -> UIImage? {
        guard hasOwner, self.owner == owner else { return nil }
        return entries.first { $0.source == source }?.image
    }

    func store(_ image: UIImage, source: OiStoryListPortraitSource, owner: UUID?) {
        useOwner(owner)
        entries.removeAll { $0.source == source }
        entries.append(Entry(source: source, image: image))
        if entries.count > 8 { entries.removeFirst(entries.count - 8) }
    }

    func clear() { entries.removeAll() }
}

/// One list owns one capture surface. Completed, normalized images need no live renderer.
@MainActor @Observable
final class OiStoryListPortraits {
    struct Request: Equatable {
        let id: UUID
        let source: OiStoryListPortraitSource
    }

    struct Input: Equatable {
        let owner: UUID?
        let requests: [Request]
        let isActive: Bool
        let retry: Int
    }

    struct Capture: Identifiable {
        let id = UUID()
        let source: OiStoryListPortraitSource

        var look: OiWardrobeLook {
            if case .wardrobe(let look) = source { return look }
            if case .seedWithPhotos(_, let look) = source { return look }
            return OiWardrobeLook()
        }
        var seed: OiSeedCucumberSnapshot? {
            if case .seed(let seed) = source { return seed }
            if case .seedWithPhotos(let seed, _) = source { return seed }
            return nil
        }
    }

    enum Result {
        case ready(UIImage)
        case failed
    }

    private struct Entry {
        let source: OiStoryListPortraitSource
        let result: Result
    }

    private enum PortraitError: Error { case unavailable }

    private(set) var capture: Capture?
    private var entries: [UUID: Entry] = [:]
    private var owner: UUID?
    private var generation = 0
    @ObservationIgnored private var pending: (id: UUID, continuation: CheckedContinuation<Data, Error>)?

    func result(for request: Request, owner: UUID?) -> Result? {
        let entry = owner == self.owner ? entries[request.id] : nil
        if let entry, entry.source == request.source, case .ready = entry.result { return entry.result }
        if let image = OiStoryListPortraitCache.shared.image(for: request.source, owner: owner) { return .ready(image) }
        return entry?.source == request.source ? entry?.result : nil
    }

    func retry(_ id: UUID) { entries[id] = nil }

    func cancel() {
        generation += 1
        capture = nil
        let previous = pending
        pending = nil
        previous?.continuation.resume(throwing: CancellationError())
    }

    func load(_ input: Input, remote: ((String) async throws -> UIImage)?) async {
        cancel()
        if owner != input.owner { entries.removeAll() }
        owner = input.owner
        OiStoryListPortraitCache.shared.useOwner(input.owner)
        let ids = Set(input.requests.map(\.id))
        entries = entries.filter { ids.contains($0.key) }
        guard input.isActive else { return }
        let started = generation
        defer { if generation == started { capture = nil } }

        for request in input.requests {
            guard !Task.isCancelled, generation == started else { return }
            if entries[request.id]?.source == request.source { continue }
            if let image = OiStoryListPortraitCache.shared.image(for: request.source, owner: input.owner) {
                entries[request.id] = Entry(source: request.source, result: .ready(image))
                continue
            }
            if let cached = entries.values.first(where: {
                guard $0.source == request.source else { return false }
                if case .ready = $0.result { return true }
                return false
            }) {
                entries[request.id] = cached
                continue
            }
            do {
                let image: UIImage
                switch request.source {
                case .seed, .seedWithPhotos, .wardrobe:
                    let bytes = try await render(request.source, generation: started)
                    guard let decoded = UIImage(data: bytes) else { throw PortraitError.unavailable }
                    image = decoded
                case .remote(let path):
                    capture = nil
                    guard let remote else { throw PortraitError.unavailable }
                    image = try await remote(path)
                case .image(let bytes):
                    guard let decoded = UIImage(data: bytes) else { throw PortraitError.unavailable }
                    image = decoded
                case .asset(let name):
                    guard let asset = UIImage(named: name) else { throw PortraitError.unavailable }
                    image = asset
                }
                try Task.checkCancellation()
                let normalized = await OiStoryListPortraitPixels.shared.normalize(image)
                guard !Task.isCancelled, generation == started else { return }
                entries[request.id] = Entry(source: request.source, result: .ready(normalized))
                OiStoryListPortraitCache.shared.store(normalized, source: request.source, owner: input.owner)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == started else { return }
                capture = nil
                entries[request.id] = Entry(source: request.source, result: .failed)
            }
        }
    }

    private func render(_ source: OiStoryListPortraitSource, generation started: Int) async throws -> Data {
        let next = Capture(source: source)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled, generation == started else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending = (next.id, continuation)
                capture = next
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.pending?.id == next.id else { return }
                self?.cancel()
            }
        }
    }

    func finishCapture(_ id: UUID, data: Data?) {
        guard let pending, pending.id == id else { return }
        self.pending = nil
        if let data { pending.continuation.resume(returning: data) }
        else { pending.continuation.resume(throwing: PortraitError.unavailable) }
    }
}

/// Pixel work runs off the UI actor. The same alpha bounds and canvas apply to every source.
actor OiStoryListPortraitPixels {
    static let shared = OiStoryListPortraitPixels()

    func normalize(_ image: UIImage) -> UIImage { Self.normalized(image) }

    nonisolated static func normalized(_ image: UIImage) -> UIImage {
        let trimmed = OiOpaqueImageTrim.trimmed(image)
        guard let source = trimmed.cgImage,
              let context = CGContext(data: nil, width: 150, height: 234, bitsPerComponent: 8, bytesPerRow: 600,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return trimmed }
        let scale = min(150 / CGFloat(source.width), 234 / CGFloat(source.height))
        let size = CGSize(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: (150 - size.width) / 2, y: (234 - size.height) / 2,
                                       width: size.width, height: size.height))
        guard let result = context.makeImage() else { return trimmed }
        return UIImage(cgImage: result, scale: 3, orientation: .up)
    }
}
