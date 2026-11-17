import Foundation

enum OiStoryReviewRequest {
    static let title = "내용 검토 요청하기"
}

struct OiStoryListItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let cucumberName: String
    /// Story title shown under the name (Figma `5441:17267`).
    let title: String
    let cucumberAsset: String
    /// The draft's customised cucumber, when the card step has rendered one.
    let portraitPNG: Data?
    let donorDisplayName: String
    let locationDisplayName: String
    let tags: [String]
    let dateLabel: String

    init(
        id: UUID,
        cucumberName: String,
        title: String = "",
        cucumberAsset: String,
        portraitPNG: Data? = nil,
        donorDisplayName: String,
        locationDisplayName: String,
        tags: [String],
        dateLabel: String
    ) {
        self.id = id
        self.cucumberName = cucumberName
        self.title = title
        self.cucumberAsset = cucumberAsset
        self.portraitPNG = portraitPNG
        self.donorDisplayName = donorDisplayName
        self.locationDisplayName = locationDisplayName
        self.tags = Array(tags.prefix(2))
        self.dateLabel = dateLabel
    }

    init(story: OiLiveStory, portraitPNG: Data? = nil, donorDisplayName: String, locationDisplayName: String) {
        self.init(
            id: story.id,
            cucumberName: story.cucumberName,
            title: story.title,
            cucumberAsset: story.cucumberAsset,
            portraitPNG: portraitPNG,
            donorDisplayName: donorDisplayName,
            locationDisplayName: locationDisplayName,
            tags: [story.emotion, story.theme].filter { !$0.isEmpty },
            dateLabel: story.createdDateLabel
        )
    }
}

struct OiStoryPlantSelection: Equatable {
    let items: [OiStoryListItem]
    var selectedID: UUID
}

enum OiStoryListReviewState: Equatable {
    case unreviewed, reviewing, approved, rejected, lookupFailed

    var title: String {
        switch self {
        case .unreviewed: "검토 전"
        case .reviewing: "검토중"
        case .approved: "게시 가능"
        case .rejected: "수정 필요"
        case .lookupFailed: "검토 결과 확인 실패"
        }
    }

    var background: UInt32 {
        switch self {
        case .unreviewed: 0xf3f3f3
        case .reviewing: 0xfdf0df
        case .approved: 0xeaeee2
        case .rejected, .lookupFailed: 0xffe7e7
        }
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

    /// New stories are limited to four slots. Previously submitted stories remain visible until reviewed.
    static let draftCapacity = 4

    var isFull: Bool { items.count >= Self.draftCapacity }

    func slots(minimumVisibleCount: Int = Self.draftCapacity) -> [OiStoryListSlot] {
        let visibleCount = max(min(max(0, minimumVisibleCount), Self.draftCapacity), items.count)
        return (0..<visibleCount).map { index in
            OiStoryListSlot(index: index, item: items.indices.contains(index) ? items[index] : nil)
        }
    }
}

struct OiStoryListSlot: Identifiable, Equatable, Sendable {
    var id: String { item.map { "story-" + $0.id.uuidString } ?? "empty-\(index)" }
    let index: Int
    let item: OiStoryListItem?
}

extension OiStoryListState {
    static let preview: Self = .content([
        OiStoryListItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            cucumberName: "지각변동오이",
            title: "포항에서의 소중한 인연들",
            cucumberAsset: "StoryListEarthquakeCucumber",
            donorDisplayName: "26학번 디벨로퍼학과 신수리",
            locationDisplayName: "포항공과대학교 C5 앞",
            tags: ["행복함", "우정"],
            dateLabel: "2026년 10월 29일 (목)"
        ),
        OiStoryListItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            cucumberName: "과잠입었오이",
            title: "반도체 HINT 연구실의 추억",
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
            title: "아주 긴 제목을 가진 이야기도 한 줄로 보여야 해요",
            cucumberAsset: "StoryListEarthquakeCucumber",
            donorDisplayName: "26학번 아주 긴 이름의 디벨로퍼학과 기부자",
            locationDisplayName: "포항공과대학교 폭풍의 언덕과 학생회관 사이 중앙 벤치",
            tags: ["행복한추억", "오랜우정"],
            dateLabel: "2026년 10월 31일 (토)"
        )
    ])
}
