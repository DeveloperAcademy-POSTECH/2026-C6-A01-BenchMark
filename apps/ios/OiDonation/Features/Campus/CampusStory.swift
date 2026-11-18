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
    var authorID: UUID? = nil
    var donorFarmerAsset: String? = nil
    /// The story's own title, shown under the cucumber name on list cards (Figma `5441:17267`).
    var storyTitle: String = ""
    var remoteBody: String? = nil
    var remoteMediaPaths: [String] = []
    var cucumberPortraitPath: String? = nil
    var cardArtworkPath: String? = nil
    var cardBackArtworkPath: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var heightMeters: Double = 1
    var headingDegrees: Double = 0
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
    var latitude: Double? = nil
    var longitude: Double? = nil
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
    var showAuthoredPlacementAction: ((UUID) -> Void)?
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
    /// The scratch postcard behind `수집하기` (#399).
    case scratch(String)
    case storyList(continuation: OiStoryContinuationIntent?)
}

/// Carries a public story into creation without editing the account's existing drafts.
struct OiStoryContinuationIntent: Hashable {
    let parent: UUID
    let author: UUID
    let requestedBy: UUID?

    init?(story: CampusStory, requestedBy: UUID?) {
        guard !story.isExample, let parent = UUID(uuidString: story.id), let author = story.authorID,
              author != requestedBy else { return nil }
        self.parent = parent
        self.author = author
        self.requestedBy = requestedBy
    }

    @MainActor func availableParent(in store: CampusStoryStore?, for owner: UUID) -> String? {
        guard requestedBy == nil || requestedBy == owner, author != owner,
              !OiContentSafetyStore.shared.isBlocked(author),
              let story = store?.story(parent.uuidString), !story.isExample, story.authorID == author else { return nil }
        return story.id
    }
}

/// Presentation names come from the same POIs as the map, never from a coarse server region.
enum CampusStoryLocation {
    struct Place: Decodable {
        let id: String
        let name: String
        let wgs84: [Double]
    }
    private struct Catalog: Decodable { let pois: [Place] }
    private static let places: [Place] = {
        guard let url = Bundle.main.url(forResource: "campus-data", withExtension: "json") else { return [] }
        do { return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).pois }
        catch { return [] } // A missing display catalog must not mislabel an actual location.
    }()

    static func name(latitude: Double?, longitude: Double?, fallback: String) -> String {
        guard let latitude, let longitude else { return fallback }
        return nearest(latitude: latitude, longitude: longitude, places: places)?.name ?? "캠퍼스 내 선택 위치"
    }

    static func nearest(latitude: Double, longitude: Double, places: [Place]) -> Place? {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        let scale = cos(latitude * .pi / 180)
        func distance(_ place: Place) -> Double {
            let x = (place.wgs84[0] - longitude) * scale
            let y = place.wgs84[1] - latitude
            return x * x + y * y
        }
        return places.filter {
            $0.wgs84.count >= 2 && $0.wgs84.prefix(2).allSatisfy(\.isFinite) && !$0.name.isEmpty
        }.min {
            let a = distance($0), b = distance($1)
            return a == b ? $0.id < $1.id : a < b
        }
    }
}
