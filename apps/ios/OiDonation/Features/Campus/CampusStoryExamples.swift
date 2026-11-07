import Foundation

/// Bundled Figma examples. These fields are never decoded from, or sent to, the service.
struct CampusStoryExample: Hashable {
    var introduction = ""
    var body = ""
    var heroImage: String? = nil
    var cardImage: String? = nil
    var galleryImages: [String] = []
    var relatedIDs: [String] = []
}

enum CampusStoryExamples {
    // Source: Figma 메인 지도 뷰 (2876:8316), 요약 (3444:4276), 상세 (2450:4928).
    // The list repeats the same three examples. Keep one record per cucumber;
    // do not copy decorative map characters into invented donor stories/counts.
    static let stories: [CampusStory] = [
        CampusStory(id: "example-six-cats", regionID: "pond", title: "6냥이오이", image: "OiCats",
            tags: ["즐거움", "우정"], donor: "26학번 디벨로퍼학과 신수리",
            location: "포항공과대학교 지곡회관 옆 연못길", date: "2026년 10월 23일 (금)",
            order: 0, popularity: 0, palette: 0,
            example: CampusStoryExample(
                introduction: "포스텍 디벨로퍼학과 26학번 고양이 6마리들의\n약 3개월간 즐거웠던 2학기를 기억하며...",
                body: OiSampleStory.body,
                heroImage: "OiGallery02", cardImage: "OiCatsExampleCard",
                galleryImages: (1...11).map { String(format: "OiGallery%02d", $0) },
                relatedIDs: ["example-makgeolli", "example-poka"])),
        CampusStory(id: "example-makgeolli", regionID: "pond", title: "막걸리마시오이", image: "OiMakgeolli",
            tags: ["행복함", "우정"], donor: "26학번 반도체공학과 서수리",
            location: "포항공과대학교 지곡회관 앞 연못길", date: "2026년 10월 23일 (금)",
            order: 1, popularity: 0, palette: 1, example: CampusStoryExample()),
        CampusStory(id: "example-poka", regionID: "pond", title: "포카전이겼오이", image: "OiPoka",
            tags: ["소름", "학교"], donor: "25학번 기계공학과 정수리",
            location: "포항공과대학교 지곡회관 뒤 주차장 중앙", date: "2026년 10월 21일 (수)",
            order: 2, popularity: 0, palette: 2, example: CampusStoryExample())
    ]
}
