import Foundation

enum OiCreationStep: String, CaseIterable {
    case consent, story, photos, location, cucumber, card

    static let storyTextLimit = 45
    static let storyBodyByteLimit = 1_500
    static let storyPhotoLimit = 3

    var title: String {
        switch self {
        case .consent: "공개 약관"
        case .story: "이야기 작성"
        case .photos: "이미지 선택"
        case .location: "위치 설정"
        case .cucumber: "오이 커스텀"
        case .card: "카드 커스텀"
        }
    }
    var progress: Int {
        switch self { case .consent: 1; case .story, .photos, .location: 2; case .cucumber: 3; case .card: 4 }
    }
    static func stage(_ number: Int) -> Self? {
        switch number { case 1: .consent; case 2: .story; case 3: .cucumber; case 4: .card; default: nil }
    }
    var previous: Self? {
        switch self {
        case .consent: nil
        case .story: .consent
        case .photos, .location, .cucumber: .story
        case .card: .cucumber
        }
    }
    var next: Self? {
        switch self {
        case .consent, .photos, .location: .story
        case .story: .cucumber
        case .cucumber: .card
        case .card: nil
        }
    }

    func canContinue(draft: OiStoryDraft) -> Bool {
        switch self {
        // Consent is checked separately from navigation and story input at submission.
        case .consent: true
        case .story:
            [draft.title, draft.body, draft.theme, draft.emotion].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                && draft.title.count <= Self.storyTextLimit && draft.body.utf8.count <= Self.storyBodyByteLimit
                && draft.theme.count <= 30 && draft.emotion.count <= 30
        case .photos: true
        case .location:
            draft.latitude.map { $0.isFinite && (-90...90).contains($0) } == true &&
            draft.longitude.map { $0.isFinite && (-180...180).contains($0) } == true
        // The latest flow names the cucumber in the card step. Do not block the wardrobe before that field exists.
        case .cucumber: true
        case .card: draft.valid && draft.cucumberName.count <= 50
        }
    }
}

/// Editing a pending/public server record must not make its local copy writable again.
enum OiCreationAccess {
    static func canEdit(status: String?, submitted: Bool) -> Bool {
        if let status { return status == "draft" }
        return !submitted
    }

    static func canRebase(_ draft: OiStoryDraft, to story: OiLiveStory) -> Bool {
        guard story.status == "draft" else { return false }
        var serverDraft = OiStoryDraft(story: story)
        serverDraft.revision = draft.revision
        if draft.heightMeters == nil { serverDraft.heightMeters = nil }
        if draft.headingDegrees == nil { serverDraft.headingDegrees = nil }
        return serverDraft == draft
    }
}

/// Merges server attachments and local copies before applying a draft's preferred order.
enum OiEditingPhoto: Hashable, Identifiable {
    case local(UUID), uploaded(String)
    var id: String { switch self { case .local(let id): id.uuidString; case .uploaded(let path): path } }
    var orderKey: String {
        switch self {
        case .local(let id): id.uuidString
        case .uploaded(let path): Self.orderKey(for: path)
        }
    }

    nonisolated static func orderKey(for path: String) -> String {
        localPhotoID(for: path)?.uuidString ?? path
    }

    nonisolated static func applyingOrder<T>(_ preferred: [String], to values: [T], key: (T) -> String) -> [T] {
        let rank = Dictionary(preferred.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return values.enumerated().sorted { lhs, rhs in
            let left = rank[key(lhs.element)] ?? Int.max
            let right = rank[key(rhs.element)] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    nonisolated static func localPhotoID(for path: String) -> UUID? {
        guard let filename = path.split(separator: "/").last, filename.lowercased().hasSuffix(".jpg") else { return nil }
        return UUID(uuidString: String(filename.dropLast(4)))
    }

    static func ordered(local: [UUID], remote: [String], removed: [String], removedPhotoIDs: Set<UUID> = []) -> [Self] {
        let local = local.filter { !removedPhotoIDs.contains($0) }
        let localIDs = Set(local)
        let removedPaths = Set(removed)
        var represented = Set<UUID>()
        let existing: [Self] = remote.compactMap { path in
            guard !removedPaths.contains(path) else { return nil }
            if let id = localPhotoID(for: path) {
                guard !removedPhotoIDs.contains(id) else { return nil }
                if !localIDs.contains(id) { return .uploaded(path) }
                represented.insert(id)
                return .local(id)
            }
            return .uploaded(path)
        }
        return existing + local.filter { !represented.contains($0) }.map(Self.local)
    }
}
