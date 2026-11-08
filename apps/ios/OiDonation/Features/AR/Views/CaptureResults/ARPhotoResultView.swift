import SwiftUI

struct ARPhotoResultView: View {
    private let image: UIImage
    private let experiment: ARCaptureResult?
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saved = false
    @State private var notice: String?

    init(result: ARCaptureResult) {
        image = result.image
        experiment = result
    }

    init(image: UIImage) {
        self.image = image
        experiment = nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20))
                if experiment != nil {
                    Text("사진과 실험 설정이 앱에 저장되었습니다.").font(.callout)
                }
                Button(saved ? "사진 앱에 저장됨" : "사진 앱에 저장") { Task { await savePhoto() } }
                    .buttonStyle(.borderedProminent).disabled(saving || saved)
                if let experiment {
                    ShareLink("사진 · 설정 JSON 공유", items: [experiment.imageURL, experiment.metadataURL])
                    Text("화면 스냅샷 · 고해상도 카메라 원본이 아닙니다.").font(.caption).foregroundStyle(.secondary)
                }
                if let notice { Text(notice).font(.callout).accessibilityAddTraits(.updatesFrequently) }
            }
            .padding()
            .navigationTitle("촬영 결과")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }

    private func savePhoto() async {
        guard !saving, !saved else { return }
        saving = true
        defer { saving = false }
        do {
            let library = ARPhotoLibraryService()
            if let experiment { try await library.save(experiment.imageURL, as: .photo) }
            else { try await library.save(image) }
            saved = true
            notice = "사진 보관함에 저장했습니다."
        } catch { notice = "저장 실패: \(error.localizedDescription)" }
    }
}
