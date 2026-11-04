import Foundation

enum OiCreationStep: String, CaseIterable {
    case story, photos, location, cucumber, card

    var title: String {
        switch self {
        case .story: "이야기 작성"
        case .photos: "이미지 선택"
        case .location: "위치 설정"
        case .cucumber: "오이 커스텀"
        case .card: "카드 커스텀"
        }
    }
    var progress: Int {
        switch self { case .story, .photos, .location: 2; case .cucumber: 3; case .card: 4 }
    }
    var previous: Self? { Self.allCases.prefix(while: { $0 != self }).last }
    var next: Self? { Self.allCases.drop(while: { $0 != self }).dropFirst().first }

    func canContinue(draft: OiStoryDraft) -> Bool {
        switch self {
        case .story:
            [draft.title, draft.body, draft.theme, draft.emotion].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                && draft.title.count <= 100 && draft.body.count <= 10_000
                && draft.theme.count <= 30 && draft.emotion.count <= 30
        case .photos: true
        case .location:
            draft.latitude.map { $0.isFinite && (-90...90).contains($0) } == true &&
            draft.longitude.map { $0.isFinite && (-180...180).contains($0) } == true
        case .cucumber: !draft.cucumberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.cucumberName.count <= 50
        case .card: draft.valid
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
        return serverDraft == draft
    }
}

/// Keeps the displayed order equal to the server's attachment order, then appends new local photos.
enum OiEditingPhoto: Hashable, Identifiable {
    case local(UUID), uploaded(String)
    var id: String { switch self { case .local(let id): id.uuidString; case .uploaded(let path): path } }

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
