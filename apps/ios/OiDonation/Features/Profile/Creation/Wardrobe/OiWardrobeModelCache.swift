//
//  OiWardrobeModelCache.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/16/26.
//

import RealityKit
import UIKit

/// Shares only immutable source resources. Each renderer gets its own entity tree.
/// One selected model is retained; requests for other models load serially.
@MainActor final class OiWardrobeModelCache {
    static let shared = OiWardrobeModelCache()
    typealias Loader = @MainActor (URL) async throws -> Entity
    private let load: Loader
    private var source: (url: URL, entity: Entity)?
    private var pending: (url: URL, task: Task<Entity, Error>)?
    private var revision = 0
    private var observers: [NSObjectProtocol] = []

    init(observePressure: Bool = true, load: @escaping Loader = { try await Entity(contentsOf: $0) }) {
        self.load = load
        if observePressure {
            for name in [UIApplication.didReceiveMemoryWarningNotification,
                         UIApplication.didEnterBackgroundNotification,
                         ProcessInfo.thermalStateDidChangeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.clear()
                        await OiPortraitImages.shared.clear()
                    }
                })
            }
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    func clear() { revision += 1; source = nil }

    func clone(from url: URL) async throws -> Entity {
        try Task.checkCancellation()
        if let source, source.url == url { return source.entity.clone(recursive: true) }
        // A caller's cancellation cannot cancel a load another renderer is using.
        // Serial loading also bounds work when a user taps many outfits quickly.
        while let pending {
            let result = await pending.task.result
            try Task.checkCancellation()
            if pending.url == url { return try result.get().clone(recursive: true) }
            if let source, source.url == url { return source.entity.clone(recursive: true) }
        }
        source = nil
        let revision = revision
        let task = Task { @MainActor in
            defer { pending = nil }
            let entity = try await load(url)
            if self.revision == revision, ProcessInfo.processInfo.thermalState != .critical {
                source = (url, entity)
            }
            return entity
        }
        pending = (url, task)
        let entity = try await task.value
        try Task.checkCancellation()
        return entity.clone(recursive: true)
    }
}
