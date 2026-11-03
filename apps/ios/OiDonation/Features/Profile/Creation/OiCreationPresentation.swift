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
}

/// Keeps the displayed order equal to the server's attachment order, then appends new local photos.
enum OiEditingPhoto: Hashable, Identifiable {
    case local(UUID), uploaded(String)
    var id: String { switch self { case .local(let id): id.uuidString; case .uploaded(let path): path } }

    static func ordered(local: [UUID], remote: [String], removed: [String]) -> [Self] {
        var represented = Set<UUID>()
        let existing: [Self] = remote.filter { !removed.contains($0) }.map { path in
            if let id = local.first(where: { path.hasSuffix("/\($0.uuidString.lowercased()).jpg") }) {
                represented.insert(id)
                return .local(id)
            }
            return .uploaded(path)
        }
        return existing + local.filter { !represented.contains($0) }.map(Self.local)
    }
}
