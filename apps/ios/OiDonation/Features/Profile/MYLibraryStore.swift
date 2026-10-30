// Created by 이돈혁

import Foundation
import Observation

struct MYSchool: Identifiable, Hashable {
    let id: String
    let name: String
    var rawValue: String { name }
    static let postech = MYSchool(id: "postech", name: "POSTECH")
}

enum MYCollectionFilter: String, CaseIterable {
    case all = "전체보기"
    case schools = "학교별보기"
    var symbol: String { self == .all ? "rectangle.grid.3x2.fill" : "graduationcap.fill" }
}

enum MYCardSort: String, CaseIterable {
    case latest = "최신순"
    case oldest = "오래된순"
}

struct MYCard: Identifiable, Hashable {
    let id: String
    let title: String
    let image: String
    let school: MYSchool
    let order: Int
    let body: String
    let donor: String
    let date: String
    var storyID: String? = nil
    var appearance = "MYBasicCard"
}

@MainActor @Observable
final class MYLibraryStore {
    private(set) var nickname = "농부"
    private(set) var cards: [MYCard] = []
    var favoriteAction: ((MYCard) -> Void)?
    var campusStore: CampusStoryStore?
    private(set) var favorites: Set<String> = []
    var collectionFilter = MYCollectionFilter.all
    var collectionSort = MYCardSort.latest
    var pinnedOnly = false

    init() {}

    func collectionCards(school: MYSchool?, sort: MYCardSort, pinnedOnly: Bool) -> [MYCard] {
        cards.filter { (school == nil || $0.school == school) && (!pinnedOnly || favorites.contains($0.id)) }
            .sorted { sort == .latest ? $0.order < $1.order : $0.order > $1.order }
    }

    func toggleFavorite(_ card: MYCard) {
        guard cards.contains(where: { $0.id == card.id }) else { return }
        favoriteAction?(card)
    }

    func synchronize(nickname: String, cards: [MYCard], favorites: Set<String>) {
        self.nickname = nickname
        self.cards = cards
        self.favorites = favorites.intersection(Set(cards.map(\.id)))
    }

    func resetFilters() {
        collectionFilter = .all; collectionSort = .latest; pinnedOnly = false
    }
}

enum MYDestination: Hashable {
    case workshop
    case farm
    case collection
    case school(MYSchool)
}
