import PhotosUI
import SwiftUI

struct PlaquePreviewView: View {
    @Binding var message: String
    var benchID: String = ""
    var configuration: BenchPlaquePreview?
    @State private var model = PlaquePreviewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var activeSheet: EditorSheet?
    private enum EditorSheet: String, Identifiable { case placement; var id: String { rawValue } }
    private struct PhotoKey: Equatable {
        let benchID: String
        let configuration: BenchPlaquePreview?
    }
    private struct RenderKey: Equatable {
        let message: String
        let photoRevision: Int
        let placement: PlaquePhotoPlacement
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("벤치 사진 선택", systemImage: "photo")
                }
                .accessibilityIdentifier("plaque.pickPhoto")
                .disabled(model.isImporting || loadingPhoto)
                Spacer()
                Button("위치 조정", systemImage: "viewfinder") { activeSheet = .placement }
                    .disabled(model.photo == nil || model.isImporting)
            }.font(.subheadline)
            if model.isImporting || loadingPhoto { ProgressView("사진 불러오는 중…") }
            if let error = model.photoError { Text(error).font(.caption).foregroundStyle(.red) }
            VStack(alignment: .leading, spacing: 8) {
                Text("명패 확대 보기").font(.headline)
                if let images = model.images {
                    Image(images.plaque, scale: 1, label: Text("명패 확대 보기")).resizable().scaledToFit()
                        .accessibilityLabel("명패 확대 보기")
                        .accessibilityValue(images.usesPlaceholder ? "문구 입력 전 예시" : images.message)
                        .accessibilityIdentifier("plaque.closeup")
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(Color("OiSoft"))
                        .aspectRatio(170.0 / 55, contentMode: .fit)
                        .overlay { Text(model.errorMessage == nil ? "명패 준비 중…" : "문구를 확인해 주세요").font(.caption) }
                }
                Text("170 × 55mm 디자인 후보 · 실제 제작 규격은 미정")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("벤치 전체 보기").font(.headline)
                    Spacer()
                    if model.isRendering { ProgressView().controlSize(.small).accessibilityLabel("미리보기 업데이트 중") }
                }
                if let images = model.images {
                    Image(images.bench, scale: 1, label: Text("명패가 합성된 벤치 전체 보기")).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("명패가 합성된 벤치 전체 보기")
                        .accessibilityValue(images.usesPlaceholder ? "문구 입력 전 예시" : images.message)
                        .accessibilityIdentifier("plaque.benchComposite")
                } else if let photo = model.photo {
                    Image(decorative: photo, scale: 1).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .bottom) { Text("명패 합성 전 원본 사진").font(.caption).padding(8).background(.thinMaterial, in: Capsule()).padding(8) }
                } else { ContentUnavailableView("벤치 사진을 선택해 주세요", systemImage: "photo") }
                Text(model.sourceTitle).font(.caption.bold())
                Text(model.sourceExplanation).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
            if model.images?.usesPlaceholder == true {
                Text("명패의 안내 문구는 예시이며 참여 신청 문구에 저장되지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }
            Text("설치 예상 이미지입니다. 명패 제공 여부·부착 위치·마감은 학교 검토 후 확정됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            Button("예시 사진으로 돌아가기") { photoItem = nil; model.useExample() }.font(.caption)
                .disabled(model.isImporting || loadingPhoto)
        }
        .task(id: PhotoKey(benchID: benchID, configuration: configuration)) {
            photoItem = nil
            model.configure(configuration)
        }
        .task(id: RenderKey(message: message, photoRevision: model.photoRevision, placement: model.placement)) {
            await model.render(message: message)
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            let sourceRevision = model.photoRevision
            loadingPhoto = true
            defer { loadingPhoto = false }
            do {
                guard let data = try await photoItem.loadTransferable(type: Data.self) else {
                    model.failedToImportPhoto(); return
                }
                try Task.checkCancellation()
                guard model.photoRevision == sourceRevision else { return }
                await model.importPhoto(data)
                try Task.checkCancellation()
                if model.photoRevision != sourceRevision { activeSheet = .placement }
            } catch is CancellationError { }
            catch { model.failedToImportPhoto() }
        }
        .sheet(item: $activeSheet) { _ in
            PlaquePlacementEditor(photo: model.photo, placement: $model.placement)
        }
    }
}

/// Also available without an approved bench list; this experience never
/// creates a participation application or treats the sample as an assigned bench.
struct PlaquePreviewExperienceView: View {
    @State private var message = "꿈꾸는 후배들을 응원합니다."
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("오래 남길 문구").font(.headline)
                    TextField("명패에 남길 문구를 입력해 주세요", text: $message, axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("plaque.message")
                    Text("문구를 바꾸면 두 미리보기가 함께 바뀝니다.").font(.caption).foregroundStyle(.secondary)
                }
                PlaquePreviewView(message: $message)
            }.padding(20)
        }
        .navigationTitle("명패 미리보기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("입력 완료") { dismissKeyboard() } } }
    }
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    NavigationStack { PlaquePreviewExperienceView() }
}
