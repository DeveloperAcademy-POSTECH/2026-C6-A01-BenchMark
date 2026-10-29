// Created by 이돈혁

import Foundation
import Observation

@MainActor protocol CampusPlacementRepository {
    func load() throws -> [CampusPlacement]
    func save(_ placements: [CampusPlacement]) throws
}

@MainActor struct LocalCampusPlacementRepository: CampusPlacementRepository {
    let url: URL
    private struct Document: Codable {
        let schemaVersion: Int
        let placements: [CampusPlacement]
    }
    init(url: URL = URL.applicationSupportDirectory.appending(path: "OiDonation/campus-placements-v1.json")) {
        self.url = url
    }
    func load() throws -> [CampusPlacement] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 128_000 else { throw CampusPlacementError.unreadable }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.schemaVersion == 1 else { throw CampusPlacementError.unreadable }
        return try checked(document.placements)
    }
    func save(_ placements: [CampusPlacement]) throws {
        let data = try JSONEncoder().encode(Document(schemaVersion: 1, placements: checked(placements)))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func checked(_ placements: [CampusPlacement]) throws -> [CampusPlacement] {
        guard placements.count <= 20, Set(placements.map(\.id)).count == placements.count
        else { throw CampusPlacementError.invalid }
        return try placements.map { try $0.validated() }
    }
}

@MainActor @Observable final class CampusPlacementStore {
    private(set) var placements: [CampusPlacement] = []
    private(set) var ready = false
    var error: String?
    @ObservationIgnored private let repository: any CampusPlacementRepository
    @ObservationIgnored private var map: CampusMapData?
    @ObservationIgnored private var storyIDs = Set<String>()

    init(repository: (any CampusPlacementRepository)? = nil) {
        self.repository = repository ?? LocalCampusPlacementRepository()
    }
    func load(map: CampusMapData, storyIDs: Set<String>) {
        guard !ready else { return }
        self.map = map; self.storyIDs = storyIDs
        do {
            let saved = try repository.load()
            try saved.forEach(validate)
            placements = saved; ready = true; error = nil
        } catch { self.error = CampusPlacementError.unreadable.localizedDescription }
    }
    @discardableResult func save(_ placement: CampusPlacement) -> Bool {
        do {
            guard ready else { throw CampusPlacementError.unreadable }
            try validate(placement)
            var next = placements
            if let index = next.firstIndex(where: { $0.id == placement.id }) {
                next[index] = placement
            } else {
                guard next.count < 20 else { throw CampusPlacementError.capacity }
                next.append(placement)
            }
            try repository.save(next)
            placements = next; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func update(_ placement: CampusPlacement) -> Bool {
        guard placements.contains(where: { $0.id == placement.id }) else {
            error = "수정할 오이를 찾지 못했어요. 저장 목록을 다시 확인해 주세요."
            return false
        }
        return save(placement)
    }
    @discardableResult func remove(_ id: UUID) -> Bool {
        do {
            guard ready else { throw CampusPlacementError.unreadable }
            let next = placements.filter { $0.id != id }
            try repository.save(next)
            placements = next; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func validate(_ placement: CampusPlacement) throws {
        _ = try placement.validated()
        guard storyIDs.contains(placement.storyID) else { throw CampusPlacementError.unknownStory }
        guard let map, map.placementError(at: map.world(latitude: placement.latitude, longitude: placement.longitude)) == nil
        else { throw CampusPlacementError.outside }
    }
}
