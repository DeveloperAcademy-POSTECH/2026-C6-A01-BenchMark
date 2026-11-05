import Foundation

struct OiStoryListItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let cucumberName: String
    let cucumberAsset: String
    let donorDisplayName: String
    let locationDisplayName: String
    let tags: [String]
    let dateLabel: String

    init(
        id: UUID,
        cucumberName: String,
        cucumberAsset: String,
        donorDisplayName: String,
        locationDisplayName: String,
        tags: [String],
        dateLabel: String
    ) {
        self.id = id
        self.cucumberName = cucumberName
        self.cucumberAsset = cucumberAsset
        self.donorDisplayName = donorDisplayName
        self.locationDisplayName = locationDisplayName
        self.tags = Array(tags.prefix(2))
        self.dateLabel = dateLabel
    }

    init(story: OiLiveStory, donorDisplayName: String, locationDisplayName: String) {
        self.init(
            id: story.id,
            cucumberName: story.cucumberName,
            cucumberAsset: story.cucumberAsset,
            donorDisplayName: donorDisplayName,
            locationDisplayName: locationDisplayName,
            tags: [story.emotion, story.theme].filter { !$0.isEmpty },
            dateLabel: story.createdDateLabel
        )
    }
}

enum OiStoryListState: Equatable, Sendable {
    case loading
    case empty
    case content([OiStoryListItem])
    case failure(String)

    var items: [OiStoryListItem] {
        if case .content(let items) = self { return items }
        return []
    }

    func slots(minimumVisibleCount: Int = 4) -> [OiStoryListSlot] {
        let visibleCount = max(max(0, minimumVisibleCount), items.count)
        return (0..<visibleCount).map { index in
            OiStoryListSlot(index: index, item: items.indices.contains(index) ? items[index] : nil)
        }
    }
}

struct OiStoryListSlot: Identifiable, Equatable, Sendable {
    var id: Int { index }
    let index: Int
    let item: OiStoryListItem?
}

extension OiStoryListState {
    static let preview: Self = .content([
        OiStoryListItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            cucumberName: "지각변동오이",
            cucumberAsset: "StoryListEarthquakeCucumber",
            donorDisplayName: "26학번 디벨로퍼학과 신수리",
            locationDisplayName: "포항공과대학교 C5 앞",
            tags: ["행복함", "우정"],
            dateLabel: "2026년 10월 29일 (목)"
        ),
        OiStoryListItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            cucumberName: "과잠입었오이",
            cucumberAsset: "StoryListJacketCucumber",
            donorDisplayName: "익명",
            locationDisplayName: "포항공과대학교 폭풍의 언덕 중앙",
            tags: ["설렘", "학교"],
            dateLabel: "2026년 10월 21일 (수)"
        )
    ])

    static let layoutStressPreview: Self = .content([
        OiStoryListItem(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            cucumberName: "아주긴이름을가진행복한오이",
            cucumberAsset: "StoryListEarthquakeCucumber",
            donorDisplayName: "26학번 아주 긴 이름의 디벨로퍼학과 기부자",
            locationDisplayName: "포항공과대학교 폭풍의 언덕과 학생회관 사이 중앙 벤치",
            tags: ["행복한추억", "오랜우정"],
            dateLabel: "2026년 10월 31일 (토)"
        )
    ])
}
