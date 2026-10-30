// Created by 이돈혁

import Foundation
import Observation

enum MYSchool: String, CaseIterable, Identifiable {
    case postech = "POSTECH"
    case apple = "애플대학교"
    var id: String { rawValue }
}

enum MYCollectionFilter: String, CaseIterable {
    case all = "전체보기"
    case schools = "학교별보기"
    case favorites = "즐겨찾기"
    var symbol: String {
        switch self {
        case .all: "rectangle.grid.3x2.fill"
        case .schools: "graduationcap.fill"
        case .favorites: "pin.fill"
        }
    }
}

enum MYCardSort: String, CaseIterable {
    case latest = "최신순"
    case oldest = "오래된순"
}

struct MYDemoCard: Identifiable, Hashable {
    let id: String
    let title: String
    let image: String
    let school: MYSchool
    let order: Int
    let distance: Int
    let popularity: Int
    var storyID: String? = nil
}

@MainActor @Observable
final class MYDemoStore {
    private(set) var nickname = "신서임당"
    private(set) var cards: [MYDemoCard]
    var favoriteAction: ((MYDemoCard) -> Void)?
    var campusStore: CampusStoryStore?
    private(set) var favorites: Set<String> = []
    var collectionFilter = MYCollectionFilter.all
    var collectionSort = MYCardSort.latest
    var pinnedOnly = false

    init(loadExamples: Bool = true) {
        if !loadExamples { nickname = "농부"; cards = []; return }
        let titles = ["화성갈끄니까오이", "개강한대학생오이", "개강한아기오이", "6냥이오이", "대학원생갈겠오이"]
        let images = ["MYSpaceCard", "MYPostechCard", "MYHoodCard", "MYCatCard", "MYDoctorCard"]
        cards = MYSchool.allCases.flatMap { school in
            (0..<(school == .postech ? 15 : 8)).map { index in
                MYDemoCard(
                    id: "my-demo-\(school.id)-\(index)",
                    title: school == .apple ? ["6냥이오이", "연구원 오이"][index % 2] : titles[index % titles.count],
                    image: school == .apple ? ["MYCatCard", "MYDoctorCard"][index % 2] : images[index % images.count],
                    school: school, order: index + (school == .postech ? 0 : 15),
                    distance: (index * 31 + (school == .postech ? 80 : 420)) % 900,
                    popularity: (index * 37 + 120) % 200
                )
            }
        }
    }

    func visibleCards(filter: MYCollectionFilter, school: MYSchool?, sort: CampusStorySort) -> [MYDemoCard] {
        cards.filter { card in
            (school == nil || card.school == school) && (filter != .favorites || favorites.contains(card.id))
        }.sorted { first, second in
            switch sort {
            case .latest: return first.order < second.order
            case .distance: return first.distance == second.distance ? first.order < second.order : first.distance < second.distance
            case .popular: return first.popularity == second.popularity ? first.order < second.order : first.popularity > second.popularity
            }
        }
    }

    func collectionCards(school: MYSchool?, sort: MYCardSort, pinnedOnly: Bool) -> [MYDemoCard] {
        cards.filter { (school == nil || $0.school == school) && (!pinnedOnly || favorites.contains($0.id)) }
            .sorted { sort == .latest ? $0.order < $1.order : $0.order > $1.order }
    }

    func toggleFavorite(_ card: MYDemoCard) {
        if let favoriteAction { favoriteAction(card); return }
        guard cards.contains(where: { $0.id == card.id }) else { return }
        if favorites.contains(card.id) { favorites.remove(card.id) } else { favorites.insert(card.id) }
    }

    func synchronize(nickname: String, cards: [MYDemoCard], favorites: Set<String>) {
        self.nickname = nickname
        self.cards = cards
        self.favorites = favorites
    }
}

enum MYDestination: Hashable {
    case workshop
    case farm
    case collection
    case school(MYSchool)
}
