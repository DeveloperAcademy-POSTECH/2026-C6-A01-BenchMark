// Created by 이돈혁

import Foundation

@main
struct MYDemoChecks {
    @MainActor static func main() {
        let demo = MYDemoStore()
        precondition(demo.cards.count == 23)
        precondition(Set(demo.cards.map(\.id)).count == demo.cards.count)
        precondition(demo.visibleCards(filter: .all, school: .postech, sort: .latest).count == 15)
        precondition(demo.visibleCards(filter: .all, school: .apple, sort: .latest).count == 8)
        precondition(demo.visibleCards(filter: .favorites, school: nil, sort: .latest).isEmpty)
        let first = demo.cards[0]
        let apple = demo.cards[15]
        demo.toggleFavorite(first)
        demo.toggleFavorite(apple)
        precondition(demo.visibleCards(filter: .favorites, school: nil, sort: .latest).count == 2)
        precondition(demo.visibleCards(filter: .favorites, school: .postech, sort: .latest).map(\.id) == [first.id])
        demo.toggleFavorite(first)
        precondition(demo.favorites == [apple.id])
        for school in MYSchool.allCases {
            let distance = demo.visibleCards(filter: .all, school: school, sort: .distance)
            precondition(zip(distance, distance.dropFirst()).allSatisfy { $0.distance <= $1.distance })
            let popular = demo.visibleCards(filter: .all, school: school, sort: .popular)
            precondition(zip(popular, popular.dropFirst()).allSatisfy { $0.popularity >= $1.popularity })
        }
        precondition(MYDemoStore().favorites.isEmpty)
        demo.collectionFilter = .schools
        precondition(demo.collectionFilter == .schools)
        precondition(MYDemoStore().collectionFilter == .all)
        print("PASS: demo card identity, school counts, favorites, filtering, distance/popularity sorting, session isolation")
    }
}
