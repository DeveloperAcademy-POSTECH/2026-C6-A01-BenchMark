import Foundation

/// Search only information supplied by the public record; missing donor fields never
/// fall back to the cucumber nickname or private account information.
enum CampusSearchMode: String, Identifiable, CaseIterable {
    case donor, name, code
    var id: String { rawValue }
    var choice: String {
        switch self { case .donor: "학교 / 학과 / 학번 / 이름"; case .name: "오이 이름"; case .code: "오이코드 입력" }
    }
    var title: String {
        switch self { case .donor: "학교/학과/학번/이름 검색"; case .name: "오이 이름 검색"; case .code: "오이코드 검색" }
    }
}

struct CampusSearchQuery: Equatable {
    var text = ""
    var school = ""
    var department = ""
    var year = ""
    var name = ""
    var hasDonorFilter: Bool { [school, department, year, name].contains { !Self.normalized($0).isEmpty } }
    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { !$0.isWhitespace }
    }
}

/// Search has not run until a query is entered (or the donor form is submitted).
/// Cached matches remain useful during refresh; a failed lookup is never a zero result.
enum CampusSearchContentState: Equatable {
    case prompt, loading, failed, results, noMatches

    init(hasSearched: Bool, hasMatches: Bool, hasLoaded: Bool, isLoading: Bool, hasError: Bool) {
        if !hasSearched { self = .prompt }
        else if hasMatches { self = .results }
        else if isLoading { self = .loading }
        else if hasError { self = .failed }
        else if !hasLoaded { self = .loading }
        else { self = .noMatches }
    }

    var showsIllustration: Bool { self == .prompt || self == .noMatches }
}

struct CampusSearchEntry: Identifiable {
    let story: CampusStory
    let publicID: UUID?
    let cucumberName: String
    let code: String
    let school: String
    var department = ""
    var year = ""
    var donorName = ""
    var id: String { story.id }

    func matches(_ query: CampusSearchQuery, mode: CampusSearchMode) -> Bool {
        func includes(_ field: String, _ term: String) -> Bool {
            let term = CampusSearchQuery.normalized(term)
            return term.isEmpty || CampusSearchQuery.normalized(field).contains(term)
        }
        switch mode {
        case .name: return includes(cucumberName, query.text) || includes(story.title, query.text)
        case .code:
            let term = CampusSearchQuery.normalized(query.text)
            return !term.isEmpty && CampusSearchQuery.normalized(code) == term
        case .donor:
            return query.hasDonorFilter && includes(school, query.school) && includes(department, query.department)
                && (CampusSearchQuery.normalized(query.year).isEmpty ||
                    (!year.isEmpty && Self.cohort(year) == Self.cohort(query.year)))
                && includes(donorName, query.name)
        }
    }

    /// 학번 here means admission cohort (26 / 2026 / 26학번), never a full student ID.
    private static func cohort(_ value: String) -> String {
        let value = CampusSearchQuery.normalized(value).replacingOccurrences(of: "학번", with: "")
        return value.count == 4 && value.allSatisfy(\.isNumber) ? String(value.suffix(2)) : value
    }

    static func example(_ story: CampusStory) -> Self {
        let parts = story.donor.split(separator: " ").map(String.init)
        let known = parts.count == 3 && parts[0].hasSuffix("학번")
        return Self(story: story, publicID: nil, cucumberName: story.title, code: story.id,
            school: "POSTECH 포스텍 포항공과대학교", department: known ? parts[1] : "",
            year: known ? parts[0] : "", donorName: known ? parts[2] : "")
    }
}
