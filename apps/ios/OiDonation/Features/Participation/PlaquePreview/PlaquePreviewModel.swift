import Observation
import SwiftUI

@MainActor @Observable
final class PlaquePreviewModel {
    private(set) var photo: CGImage?
    private(set) var sourceTitle = "예시 벤치 사진"
    private(set) var sourceExplanation = "이 사진은 실제 POSTECH 벤치가 아닌 미리보기 예시입니다."
    var placement = PlaquePhotoPlacement.centered
    private(set) var photoRevision = 0
    private(set) var images: PlaquePreviewImages?
    private(set) var isRendering = false
    private(set) var isImporting = false
    private(set) var errorMessage: String?
    private(set) var photoError: String?
    private let renderer = PlaquePreviewRenderer()
    private var renderGeneration = 0

    init() { useExample() }

    func configure(_ configuration: BenchPlaquePreview?) {
        guard let configuration else { useExample(); return }
        guard let image = UIImage(named: configuration.assetName)?.cgImage else {
            photo = nil
            images = nil
            sourceTitle = "벤치 사진 준비 중"
            sourceExplanation = "선택한 벤치의 사진을 불러오지 못했습니다. 다른 사진으로 위치를 시험해 볼 수 있습니다."
            changedPhoto()
            return
        }
        photo = image
        placement = configuration.placement
        sourceTitle = "선택한 벤치 사진"
        sourceExplanation = "설치 예상 이미지입니다. 최종 위치와 마감은 학교 검토 후 확정됩니다."
        changedPhoto()
    }

    func useExample() {
        let original = UIImage(named: "HomeBench")?.cgImage
        // Existing photo is cropped around the entire bench, without changing
        // any of its pixels or pretending it is an approved campus bench.
        photo = original?.cropping(to: CGRect(x: 130, y: 690, width: 490, height: 330))
        placement = PlaquePhotoPlacement(topLeft: .init(x: 0.57, y: 0.15), topRight: .init(x: 0.74, y: 0.175),
                                        bottomRight: .init(x: 0.74, y: 0.25), bottomLeft: .init(x: 0.57, y: 0.225))
        sourceTitle = "예시 벤치 사진"
        sourceExplanation = "이 사진은 실제 POSTECH 벤치가 아닌 미리보기 예시입니다."
        changedPhoto()
    }

    func importPhoto(_ data: Data) async {
        isImporting = true; photoError = nil
        defer { isImporting = false }
        do {
            let image = try await renderer.loadPhoto(data: data)
            try Task.checkCancellation()
            photo = image
            placement = .centered
            sourceTitle = "선택한 벤치 사진"
            sourceExplanation = "선택한 사진에서 예상 위치를 직접 지정합니다. 학교가 승인한 부착 위치는 아닙니다."
            changedPhoto()
        } catch is CancellationError { }
        catch { photoError = "사진을 불러오지 못했어요. 30MB 이하의 다른 사진을 선택해 주세요." }
    }

    func failedToImportPhoto() { photoError = "사진을 불러오지 못했어요. 다시 선택해 주세요." }

    private func changedPhoto() {
        renderGeneration += 1
        isRendering = false
        photoRevision += 1
        images = nil
        errorMessage = nil
        photoError = nil
    }

    func render(message: String) async {
        renderGeneration += 1
        let token = renderGeneration
        guard let photo else { images = nil; isRendering = false; errorMessage = nil; return }
        isRendering = true
        errorMessage = nil
        let corners = placement
        defer { if renderGeneration == token { isRendering = false } }
        do {
            // Coalesce keystrokes/drag updates; drawing runs on the renderer actor.
            try await Task.sleep(for: .milliseconds(80))
            let result = try await renderer.render(message: message, photo: photo, placement: corners)
            try Task.checkCancellation()
            guard token == renderGeneration else { return }
            images = result
        } catch is CancellationError { }
        catch {
            guard token == renderGeneration else { return }
            images = nil
            errorMessage = error.localizedDescription
        }
    }
}
