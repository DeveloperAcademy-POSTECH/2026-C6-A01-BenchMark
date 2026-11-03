#if DEBUG
import Foundation
import Observation

/// In-memory only. No remote store, account, writing grant, or persistence dependency.
@MainActor @Observable
final class OiCreationPracticeSession {
    struct Photo: Identifiable { let id: UUID; let data: Data }
    var draft = OiStoryDraft()
    var customization = OiDraftCustomization()
    private(set) var photos: [Photo] = []
    private(set) var completed = false

    var canReview: Bool {
        [.story, .photos, .location, .cucumber].allSatisfy { (step: OiCreationStep) in step.canContinue(draft: draft) }
    }
    func fillExampleText() {
        draft.title = "오래 남기고 싶은 우리 이야기"
        draft.body = "함께한 순간을 캠퍼스에 남깁니다. 서로를 응원하며 다시 만날 날을 기다려요."
        draft.theme = "우정"; draft.emotion = "고마움"; draft.cucumberName = "우리의 오이"
    }
    func addPhoto(_ data: Data) throws {
        photos.append(Photo(id: UUID(), data: try OiPhotoProcessor.prepare(data)))
    }
    func editPhoto(_ id: UUID, operation: OiPhotoEdit) throws {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { throw OiServiceError.invalidInput }
        let data = try OiPhotoProcessor.edit(photos[index].data, operation: operation)
        photos[index] = Photo(id: UUID(), data: data)
    }
    func removePhoto(_ id: UUID) { photos.removeAll { $0.id == id } }
    @discardableResult func completePractice() -> Bool {
        guard canReview else { return false }
        completed = true
        return true
    }
    func reset() {
        draft = OiStoryDraft(); customization = OiDraftCustomization()
        photos = []; completed = false
    }
}
#endif
