#if DEBUG
import PhotosUI
import SwiftUI

/// Uses the actual step UI with an isolated, disposable in-memory session.
struct OiCreationPreviewHost: View {
    @State private var session = OiCreationPracticeSession()
    @State private var step: OiCreationStep = .story
    @State private var locationRequest: OiLocationPickerRequest?
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var preparingPhotos = false
    @State private var localError: String?
    @State private var reviewing = false
    @State private var choosingExit = false
    @Environment(\.dismiss) private var dismiss
    private let assets = [OiAsset(id: "OiCats", kind: "cucumber", name: "기본 세트"), OiAsset(id: "MYBasicCard", kind: "card", name: "기본 카드")]
    private var isPhotoStep: Bool { step == .photos && !session.completed }
    private var canContinue: Bool { !preparingPhotos && (step == .card ? session.canReview : step.canContinue(draft: session.draft)) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(session.completed ? "체험 완료" : step.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationControls }
                .toolbarColorScheme(isPhotoStep ? .dark : .light, for: .navigationBar)
                .toolbarBackground(isPhotoStep ? Color(white: 0.14) : Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .environment(\.colorScheme, isPhotoStep ? .dark : .light)
                .fullScreenCover(item: $locationRequest) { request in
                    OiLocationPicker(latitude: $session.draft.latitude, longitude: $session.draft.longitude, focusPlaceID: request.focusPlaceID)
                }
                .sheet(isPresented: $reviewing) { review }
                .confirmationDialog("체험을 종료할까요?", isPresented: $choosingExit, titleVisibility: .visible) {
                    Button("입력 내용 지우고 종료", role: .destructive) { session.reset(); dismiss() }
                    Button("계속 체험", role: .cancel) {}
                } message: { Text("체험 중 작성한 글과 사진 복사본·위치·색상은 저장되지 않습니다. 원본 사진은 삭제하지 않아요.") }
                .task(id: photoSelections) { await importPhotos() }
        }
        .preferredColorScheme(isPhotoStep ? .dark : .light)
        .interactiveDismissDisabled()
    }

    private var content: some View {
        VStack(spacing: 0) {
            Text("작성 체험 · 서버 전송 없음 · 종료 시 입력 삭제")
                .font(.caption).frame(maxWidth: .infinity).padding(10)
                .foregroundStyle(Color("OiGreen")).background(Color("OiLight"))
            if session.completed { completion }
            else {
                if !isPhotoStep { OiCreationProgressHeader(step: step.progress).padding(.horizontal, 20).padding(.vertical, 8) }
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Color.clear.frame(height: 1).id("practice.top")
                            if let localError { Text(localError).font(.footnote).foregroundStyle(.red) }
                            if preparingPhotos { ProgressView("사진 불러오는 중") }
                            stepContent
                        }.padding(20)
                    }.scrollDismissesKeyboard(.interactively)
                        .onChange(of: step) { _, _ in scroll.scrollTo("practice.top", anchor: .top) }
                }
                OiCreationNextButton(title: step == .card ? "미리보기·검토 요청 체험" : "다음", enabled: canContinue) {
                    localError = nil
                    if let next = step.next { step = next } else { reviewing = true }
                }.accessibilityIdentifier("oi.practice.next").padding(.horizontal, 20).padding(.vertical, 10)
            }
        }.background(isPhotoStep ? Color(white: 0.14) : Color.white)
    }

    @ToolbarContentBuilder private var navigationControls: some ToolbarContent {
        if !session.completed, let previous = step.previous {
            ToolbarItem(placement: .topBarLeading) {
                Button("이전", systemImage: "chevron.left") { step = previous }.disabled(preparingPhotos)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("체험 종료") {
                if session.completed { session.reset(); dismiss() } else { choosingExit = true }
            }.disabled(preparingPhotos)
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .story:
            Button("예시 문구 채우기") { session.fillExampleText() }.buttonStyle(.bordered)
            OiStoryWritingStep(draft: $session.draft, grants: [])
        case .photos:
            OiStoryPhotoStep(items: session.photos.map { .local($0.id) }, uploadedPhotos: [], selections: $photoSelections,
                edit: { id, operation in
                    do { try session.editPhoto(id, operation: operation); localError = nil }
                    catch { localError = "사진을 편집하지 못했어요. 다른 사진으로 다시 시도해 주세요." }
                }, remove: { item in
                    if case .local(let id) = item { session.removePhoto(id) }
                }, photo: photo)
                .disabled(preparingPhotos)
        case .location:
            OiStoryLocationStep(draft: $session.draft, regions: []) { placeID in
                locationRequest = OiLocationPickerRequest(focusPlaceID: placeID)
            }
        case .cucumber:
            OiCucumberCustomizationStep(draft: $session.draft, customization: $session.customization, assets: assets)
        case .card:
            OiCardCustomizationStep(draft: $session.draft, customization: $session.customization, assets: assets)
        }
    }

    @ViewBuilder private func photo(_ item: OiEditingPhoto) -> some View {
        if case .local(let id) = item, let data = session.photos.first(where: { $0.id == id })?.data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("체험에 첨부한 사진")
        }
    }

    private var review: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    OiDraftCardPreview(draft: session.draft, customization: session.customization).frame(height: 300).frame(maxWidth: .infinity)
                    Text(session.draft.title).font(.title2.bold())
                    Text(session.draft.body)
                    Text("\(session.draft.theme) · \(session.draft.emotion) · \(session.draft.cucumberName)").font(.subheadline)
                    if let lat = session.draft.latitude, let lon = session.draft.longitude {
                        Text(String(format: "선택 위치: %.7f, %.7f", lat, lon)).font(.caption)
                    }
                    ForEach(session.photos) { item in photo(.local(item.id)).frame(maxWidth: .infinity).frame(height: 200) }
                    Text("체험용 확인 화면이에요. 글·사진·위치는 운영자에게 전송되지 않고, 지도와 AR에도 공개되지 않아요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    OiCreationNextButton(title: "검토 요청 체험", enabled: session.canReview) {
                        if session.completePractice() { reviewing = false }
                    }.accessibilityIdentifier("oi.practice.submit")
                }.padding(20)
            }.navigationTitle("검토 요청 미리보기").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("계속 수정") { reviewing = false } } }
        }.preferredColorScheme(.light)
    }

    private var completion: some View {
        ScrollView {
            VStack(spacing: 24) {
                OiDraftCardPreview(draft: session.draft, customization: session.customization).frame(height: 320)
                Label("검토 요청 체험을 마쳤어요", systemImage: "checkmark.circle.fill").font(.headline)
                Text("실제 요청은 접수되지 않았어요.\n실제 공개에는 증빙 검토·작성 승인과 운영자의 이야기 승인이 필요해요.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                OiCreationNextButton(title: "이야기 목록으로 돌아가기") { session.reset(); dismiss() }
                Button("처음부터 다시 체험") { session.reset(); step = .story; localError = nil }
            }.padding(24).frame(maxWidth: .infinity)
        }
    }

    private func importPhotos() async {
        let selections = photoSelections
        guard !selections.isEmpty else { return }
        preparingPhotos = true; localError = nil
        defer { preparingPhotos = false; photoSelections = [] }
        var failures = 0
        for selection in selections {
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw OiServiceError.invalidInput }
                try Task.checkCancellation()
                try session.addPhoto(data)
            } catch is CancellationError { return }
            catch { failures += 1 }
        }
        if failures > 0 { localError = "\(failures)장의 사진을 추가하지 못했어요. 사진을 다시 선택해 주세요." }
    }
}
#endif
