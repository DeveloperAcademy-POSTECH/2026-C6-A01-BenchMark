import Foundation
import Observation

/// Figma fixtures only. These records are not verified donations or live school data.
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

    var isCats: Bool { image == "OiCats" }
    var excerpt: String {
        isCats ? "포스텍 디벨로퍼학과 26학번의 고양이 6마리들의\n약 3개월간 즐거웠던 2학기를 기억하며..." : "캠퍼스에서 함께한 순간을 오래 기억하고 싶어요."
    }
    var gallery: [String] { isCats ? (1...11).map { String(format: "OiGallery%02d", $0) } : [] }
    var body: String {
        guard isCats else { return "이 이야기는 새 디자인을 확인하기 위한 예시입니다. 공개에 동의한 기부자의 이야기와 사진이 준비되면 이곳에 연결됩니다." }
        return """
        포스텍26학번 오후분반 6냥이들아,
        한 학기동안 우리 힘든 일도 있었지만
        너희덕분에 너무 행복한 교양수업이 될 수 있었어.

        처음 프렐류드 때 너희를 만났을 때가 엊그제같은데,
        벌써 우리가 만난지 8개월이 되었네.
        이번 2학기때 우리들이 같은 교양수업에 같은 팀이 되면서
        더 가까워지고 돈독해질 수 있는 팀플이었던 것 같아.

        팀에 필요한 걸 다 해결해주는 지훈이,
        뭐든 뚝딱 만들어내는 돈혁이,
        빈부분을 매번 채워주는 예은이,
        긍정파워로 모두를 도와주는 윤진이,
        항상 배우려고 노력하는 지원이.

        우리 다음 학기에도 그 다음 학기에도
        자주 만나서 즐거운 시간 많이 보냈으면 좋겠다.
        사랑하는 6냥이들... 우리 앞으로 평생 행복하자!!
        """
    }
}

struct CampusRegion: Identifiable, Hashable {
    let id: String
    let title: String
    let placeID: String
    let sampleCount: Int
    static let examples: [Self] = [
        .init(id: "pond", title: "지곡회관 · 연못", placeID: "97", sampleCount: 11),
        .init(id: "library", title: "박태준학술정보관", placeID: "72", sampleCount: 3),
        .init(id: "student", title: "학생회관", placeID: "88", sampleCount: 8),
        .init(id: "dorm", title: "생활관", placeID: "75", sampleCount: 5),
        .init(id: "science", title: "생명과학관", placeID: "7", sampleCount: 26),
        .init(id: "c5", title: "C5 · 아카데미", placeID: "53", sampleCount: 14)
    ]
}

enum CampusStorySort: String, CaseIterable { case latest = "최신순", distance = "거리순", popular = "인기순" }

@MainActor @Observable
final class CampusStoryStore {
    let stories: [CampusStory]
    private(set) var collected: Set<String>
    private let defaults: UserDefaults
    private static let collectionKey = "campus.designExample.collectedIDs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collected = Set(defaults.stringArray(forKey: Self.collectionKey) ?? [])
        let images = ["OiCats", "OiMakgeolli", "OiPoka", "OiRaincoat", "OiGardener", "OiWizard", "OiPink", "OiOrange", "OiScientist", "OiBlue", "OiTraveler"]
        let names = ["6냥이오이", "막걸리오이", "포카전오이", "비 오는 날의 오이", "정원사오이", "마법사오이", "봄날의오이", "응원오이", "연구실오이", "푸른오이", "여행자오이"]
        stories = CampusRegion.examples.flatMap { region in
            (0..<region.sampleCount).map { i in
                let index = i % images.count
                return CampusStory(id: "\(region.id)-\(i)", regionID: region.id, title: names[index], image: images[index],
                    tags: index == 1 ? ["만취", "우정"] : index == 2 ? ["전율", "단합"] : ["즐거움", "우정"],
                    donor: index == 0 ? "26학번 디벨로퍼학과 신서연" : index == 1 ? "24학번 반도체공학과 서보민" : index == 2 ? "25학번 기계공학과 정서영" : "캠퍼스 이야기 · 디자인 예시",
                    location: region.id == "pond" ? "지곡회관 옆 연못길 벤치" : "포항공과대학교 \(region.title)",
                    date: index == 0 ? "2026년 10월 24일 토요일" : index == 1 ? "2026년 10월 23일 금요일" : "2026년 10월 21일 수요일",
                    order: i, popularity: (i * 37 + 120) % 200, palette: index % 3)
            }
        }
    }
    func story(_ id: String) -> CampusStory? { stories.first { $0.id == id } }
    func stories(in regionID: String, sortedBy sort: CampusStorySort, distances: [String: Float] = [:]) -> [CampusStory] {
        stories.filter { $0.regionID == regionID }.sorted { a, b in
            switch sort {
            case .latest: return a.order < b.order
            case .popular: return a.popularity == b.popularity ? a.order < b.order : a.popularity > b.popularity
            case .distance:
                let ad = distances[a.id] ?? .greatestFiniteMagnitude, bd = distances[b.id] ?? .greatestFiniteMagnitude
                return ad == bd ? a.order < b.order : ad < bd
            }
        }
    }
    func collect(_ story: CampusStory) {
        guard collected.insert(story.id).inserted else { return }
        defaults.set(collected.sorted(), forKey: Self.collectionKey)
    }
}

enum CampusDestination: Hashable {
    case summary(String)
    case story(String)
}
