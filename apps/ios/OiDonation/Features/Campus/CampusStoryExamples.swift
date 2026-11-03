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
            tags: ["즐거움", "우정"], donor: "26학번 디벨로퍼학과 신서연",
            location: "포항공과대학교 지곡회관 옆 연못길", date: "2026년 10월 23일 (금)",
            order: 0, popularity: 0, palette: 0,
            example: CampusStoryExample(
                introduction: "포스텍 디벨로퍼학과 26학번 고양이 6마리들의\n약 3개월간 즐거웠던 2학기를 기억하며...",
                body: """
                포스텍26학번 오후분반 6냥이들아,
                한 학기동안 우리 힘든 일도 있었지만
                너희덕분에 너무 행복한 교양수업이 될 수 있었어.

                처음 프렐류드 때 너희를 만났을 때가 엊그제같은데,
                벌써 우리가 만난지 8개월이 되었네.
                2학기때 우리들이 같은 교양수업에 같은 팀이 되면서
                더 가까워지고 돈독해질 수 있는 팀플이었던 것 같아.

                팀에 필요한 걸 다 해결해주는 지훈이,
                뭐든 뚝딱 만들어내는 돈혁이,
                빈부분을 매번 채워주는 예은이,
                긍정파워로 모두를 도와주는 윤진이,
                항상 배우려고 노력하는 지원이.

                우리 다음 학기에도 그 다음 학기에도
                자주 만나서 즐거운 시간 많이 보냈으면 좋겠다.
                사랑하는 6냥이들... 우리 앞으로 평생 행복하자!!
                """,
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
