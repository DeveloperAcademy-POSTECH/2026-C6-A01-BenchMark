import SwiftUI

struct ARPhotoResultView: View {
    let result: ARCaptureResult
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saved = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: result.image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20))
                Text("사진과 촬영 설정이 이 기기에 저장되었습니다.").font(.callout)
                Button(saved ? "사진 앱에 저장됨" : "사진 앱에 저장") { Task { await savePhoto() } }
                    .buttonStyle(.borderedProminent).disabled(saving || saved)
                ShareLink("사진 공유", item: result.imageURL)
                Text("화면 스냅샷 · 고해상도 카메라 원본이 아닙니다.").font(.caption).foregroundStyle(.secondary)
                if let notice { Text(notice).font(.callout).accessibilityAddTraits(.updatesFrequently) }
            }
            .padding()
            .navigationTitle("촬영 결과")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }

    private func savePhoto() async {
        saving = true
        defer { saving = false }
        do {
            try await ARPhotoLibraryService().save(result.imageURL, as: .photo)
            saved = true
            notice = "사진 보관함에 저장했습니다."
        } catch { notice = "저장 실패: \(error.localizedDescription)" }
    }
}
