import Foundation
import Observation

/// A public story projected from the server into the campus renderer.
struct CampusStory: Identifiable, Hashable {
    let id: String
    let regionID: String
    let title: String
    let image: String
    let tags: [String]
    let donor: String
    let location: String
    let date: String
    let order: Int
    let popularity: Int
    let palette: Int
    var remoteBody: String? = nil
    var remoteMediaPaths: [String] = []
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Local design content is never a public donation or a server collection target.
    var example: CampusStoryExample? = nil

    var portraitImage: String { image == "OiCats" ? "OiCatsPortrait" : image }
    var isExample: Bool { example != nil }

    var excerpt: String { example?.introduction ?? String((remoteBody ?? "").prefix(120)) }
    var body: String { example?.body ?? remoteBody ?? "" }

}

struct CampusRegion: Identifiable, Hashable {
    let id: String
    let title: String
    let placeID: String
    static let campus: [Self] = [
        .init(id: "pond", title: "지곡회관 · 연못", placeID: "97"),
        .init(id: "library", title: "박태준학술정보관", placeID: "72"),
        .init(id: "student", title: "학생회관", placeID: "88"),
        .init(id: "dorm", title: "생활관", placeID: "75"),
        .init(id: "science", title: "생명과학관", placeID: "7"),
        .init(id: "c5", title: "C5 · 아카데미", placeID: "53")
    ]
}

enum CampusStorySort: String, CaseIterable { case latest = "최신순", oldest = "오래된순", distance = "거리순", popular = "인기순" }

@MainActor @Observable
final class CampusStoryStore {
    let isExample: Bool
    private(set) var stories: [CampusStory]
    var collectAction: ((CampusStory) -> Void)?
    var createStoryAction: (() -> Void)?
    var mediaURL: ((String) async throws -> URL)?
    private(set) var collected: Set<String>

    init(defaults: UserDefaults = .standard, isExample: Bool = false) {
        self.isExample = isExample
        defaults.removeObject(forKey: "campus.designExample.collectedIDs.v1")
        stories = []; collected = []
    }
    func story(_ id: String) -> CampusStory? { stories.first { $0.id == id } }
    func stories(in regionID: String? = nil, matching ids: Set<String>? = nil,
                 sortedBy sort: CampusStorySort, distances: [String: Float] = [:]) -> [CampusStory] {
        stories.filter { story in
            (regionID == nil || story.regionID == regionID) && (ids?.contains(story.id) ?? true)
        }.sorted { a, b in
            switch sort {
            case .latest: return a.order < b.order
            case .oldest: return a.order > b.order
            case .popular: return a.popularity == b.popularity ? a.order < b.order : a.popularity > b.popularity
            case .distance:
                let ad = distances[a.id] ?? .greatestFiniteMagnitude, bd = distances[b.id] ?? .greatestFiniteMagnitude
                return ad == bd ? a.order < b.order : ad < bd
            }
        }
    }
    func collect(_ story: CampusStory) {
        guard !isExample, !story.isExample,
              let stored = stories.first(where: { $0.id == story.id }), !stored.isExample else { return }
        collectAction?(stored)
    }

    func synchronize(stories: [CampusStory], collected: Set<String>) {
        self.stories = stories.filter { $0.isExample == isExample }
        self.collected = isExample ? [] : collected
    }
}

enum CampusDestination: Hashable {
    case summary(String)
    case story(String)
}
