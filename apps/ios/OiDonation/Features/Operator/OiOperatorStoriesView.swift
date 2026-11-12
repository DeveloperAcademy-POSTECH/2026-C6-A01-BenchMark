import SwiftUI

struct OiOperatorStoriesView: View {
    let remote: OiRemoteStore
    @State private var model = OiOperatorStoriesModel()
    @State private var selected: Selection?
    private struct Selection: Identifiable, Hashable { let id: UUID }

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Picker("이야기 상태", selection: $model.filter) {
                    ForEach(OiOperatorStoryFilter.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("operator.stories.filter")
            }
            if model.isLoading {
                Section { ProgressView("검토할 이야기를 불러오는 중") }
            } else if let error = model.error {
                Section {
                    Label("이야기를 불러오지 못했어요", systemImage: "wifi.exclamationmark")
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("다시 불러오기") { Task { await model.load(using: remote) } }
                }.accessibilityIdentifier("operator.stories.error")
            } else if model.hasLoaded {
                if model.filtered.isEmpty {
                    ContentUnavailableView("\(model.filter.title) 이야기가 없어요", systemImage: "text.book.closed",
                        description: Text("다른 상태를 선택하거나 목록을 새로고침해 주세요."))
                        .accessibilityIdentifier("operator.stories.empty")
                } else {
                    Section("\(model.filter.title) · \(model.filtered.count)건") {
                        ForEach(model.filtered) { story in
                            Button { selected = Selection(id: story.id) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(story.title).font(.headline).foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(story.cucumberName).font(.subheadline).foregroundStyle(.secondary)
                                        HStack {
                                            OiOperatorStoryStatus(status: story.status)
                                            Text(story.createdDateLabel).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("operator.stories.row.\(story.id.uuidString)")
                        }
                    }
                }
            }
        }
        .navigationTitle("이야기 검토")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("새로고침", systemImage: "arrow.clockwise") { Task { await model.load(using: remote) } }
                    .disabled(model.isLoading || remote.isBusy)
            }
        }
        .task { await model.load(using: remote) }
        .refreshable { await model.load(using: remote) }
        .navigationDestination(item: $selected) { value in
            OiOperatorStoryDetailView(remote: remote, storyID: value.id) { model.apply($0) }
        }
        .privacySensitive()
    }
}

struct OiOperatorStoryDetailView: View {
    let remote: OiRemoteStore
    let storyID: UUID
    var onUpdated: (OiLiveStory) -> Void = { _ in }
    @State private var model = OiOperatorStoryModel()
    @State private var confirmation: OiLiveStory?
    @State private var showingConfirmation = false
    @State private var checkedAppearance: OiCucumberArtworkReference?
    @State private var appearanceImages: [OiCucumberArtworkReference.Part: UIImage] = [:]
    @State private var checkedCard: (path: String, image: UIImage)?
    @State private var appearanceError = false
    @State private var imageAttempt = 0
    @State private var selectedArtwork: ReviewArtwork?
    @Environment(\.scenePhase) private var phase

    private struct ReviewArtwork: Identifiable {
        let id: String
        let title: String
        let image: UIImage
    }

    private var artwork: OiCucumberArtworkReference? { model.detail?.story.cucumberArtwork }
    private var cardPath: String? { model.detail?.story.cardArtworkPath }
    private var artworkReady: Bool {
        (artwork == nil || checkedAppearance == artwork) && (cardPath == nil || checkedCard?.path == cardPath)
    }

    var body: some View {
        List {
            if model.isLoading {
                Section { ProgressView("이야기와 첨부 사진을 확인하는 중") }
            }
            if let notice = model.notice {
                Section { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    .accessibilityIdentifier("operator.story.success")
            }
            if let warning = model.warning { Section { Text(warning).font(.footnote).foregroundStyle(.secondary) } }
            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    reloadButton
                }.accessibilityIdentifier("operator.story.error")
            }
            if let detail = model.detail {
                content(detail)
            } else if !model.isLoading && model.error == nil {
                ContentUnavailableView("이야기를 확인해 주세요", systemImage: "text.book.closed")
                reloadButton
            }
            if model.requiresReload && model.warning != nil { Section { reloadButton } }
        }
        .navigationTitle("이야기 검토 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("새로고침", systemImage: "arrow.clockwise") { reload() }
                    .disabled(model.isLoading || model.isProcessing || remote.isBusy)
            }
        }
        .task(id: storyID) { await loadLatest() }
        .task(id: ArtworkLoad(artwork: artwork, cardPath: cardPath, attempt: imageAttempt)) {
            await loadArtwork(artwork, cardPath: cardPath)
        }
        .fullScreenCover(item: $selectedArtwork) { selection in
            CampusArtworkOverlay(title: selection.title) { Image(uiImage: selection.image).resizable().scaledToFit() }
        }
        .refreshable {
            confirmation = nil; showingConfirmation = false
            await loadLatest()
        }
        .confirmationDialog("공개 상태를 변경할까요?", isPresented: $showingConfirmation,
                            titleVisibility: .visible, presenting: confirmation) { story in
            let publish = story.status != "published"
            Button(publish ? "확인하고 공개" : "확인하고 비공개") {
                Task {
                    guard phase == .active, !publish || artworkReady else { return }
                    if let saved = await model.review(story, publish: publish, using: remote) { onUpdated(saved) }
                    confirmation = nil
                }
            }
            Button("취소", role: .cancel) { confirmation = nil }
        } message: { story in
            Text(story.status == "published"
                 ? "‘\(story.title)’을 공개 목록에서 내리고 숨김 상태로 보관합니다."
                 : "‘\(story.title)’의 내용과 사진, 위치, 꾸민 오이와 카드를 확인했나요? 승인하면 다른 이용자가 볼 수 있습니다.")
        }
        .interactiveDismissDisabled(model.isProcessing)
        .privacySensitive()
    }

    @ViewBuilder private func content(_ detail: OiOperatorStoryDetail) -> some View {
        let story = detail.story
        Section("이야기") {
            Text(story.title).font(.title3.bold()).textSelection(.enabled)
            OiOperatorStoryStatus(status: story.status)
            Text(story.body).textSelection(.enabled)
        }
        Section("등록 정보") {
            LabeledContent("오이 이름", value: story.cucumberName)
            LabeledContent("작성자", value: remote.profiles.first { $0.id == story.userId }?.nickname ?? "작성자 정보 없음")
            LabeledContent("등록일", value: story.createdDateLabel)
            LabeledContent("주제", value: story.theme)
            LabeledContent("감정", value: story.emotion)
        }
        Section("배치 위치") {
            LabeledContent("구역", value: remote.regions.first { $0.id == story.regionId }?.name ?? story.regionId)
            LabeledContent("위도", value: String(format: "%.6f", story.latitude))
            LabeledContent("경도", value: String(format: "%.6f", story.longitude))
            Text("작성자가 선택한 위치입니다. 현장 방문이나 학교의 설치 승인을 의미하지 않습니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("첨부 사진 · \(detail.media.count)장") {
            if detail.media.isEmpty {
                Text("첨부된 사진이 없어요.").foregroundStyle(.secondary)
            } else {
                ForEach(detail.media) { media in
                    OiStoryMediaImage(path: media.objectPath) { path in
                        try await remote.mediaURL(bucket: "oi-story-media", path: path)
                    }
                    .frame(minHeight: 120, maxHeight: 320)
                    .accessibilityLabel("첨부 사진 \(media.position + 1)")
                }
            }
        }
        if let reference = story.cucumberArtwork {
            Section("공개 오이 외형") {
                if checkedAppearance == reference {
                    ForEach(reference.parts, id: \.self) { part in
                        if let image = appearanceImages[part] {
                            let title = part == .portrait ? "지도와 카드에 표시할 오이" : (part == .top ? "상의 또는 세트" : "하의")
                            Button {
                                selectedArtwork = ReviewArtwork(id: part.rawValue, title: title, image: image)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(title).font(.subheadline)
                                    if part != .portrait { Text("왼쪽 앞면 · 오른쪽 뒷면").font(.caption).foregroundStyle(.secondary) }
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                } else if appearanceError {
                    Text("공개 오이의 외형을 확인하지 못했어요.")
                    Button("외형 다시 불러오기") { imageAttempt += 1 }
                } else {
                    ProgressView("옷과 적용한 사진을 확인하는 중")
                }
            }
        }
        if let path = story.cardArtworkPath {
            Section("작성자가 꾸민 카드") {
                if let checkedCard, checkedCard.path == path {
                    Button {
                        selectedArtwork = ReviewArtwork(id: path, title: "작성자가 꾸민 카드", image: checkedCard.image)
                    } label: {
                        Image(uiImage: checkedCard.image).resizable().scaledToFit().frame(maxHeight: 320)
                    }.buttonStyle(.plain).accessibilityLabel("꾸민 카드 크게 보기")
                } else if appearanceError {
                    Text("카드 이미지를 확인하지 못했어요.")
                    Button("카드 다시 불러오기") { imageAttempt += 1 }
                } else {
                    ProgressView("꾸민 카드를 불러오는 중")
                }
            }
        }
        Section("공개 검토") {
            if model.isProcessing { ProgressView("공개 상태를 처리하는 중") }
            Button {
                confirmation = story; showingConfirmation = true
            } label: {
                Label(story.status == "published" ? "비공개로 변경" : "공개 승인",
                      systemImage: story.status == "published" ? "eye.slash" : "checkmark.seal")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canReview || remote.isBusy || !remote.isOperator || remote.needsReauthentication
                      || (story.status != "published" && !artworkReady))
            .accessibilityIdentifier("operator.story.review")
            Text("이야기와 사진, 꾸민 오이와 카드를 검토해 공개 여부를 결정합니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var reloadButton: some View {
        Button("최신 내용 다시 불러오기", action: reload)
            .disabled(model.isLoading || model.isProcessing || remote.isBusy)
            .accessibilityIdentifier("operator.story.reload")
    }

    private func reload() {
        confirmation = nil; showingConfirmation = false
        Task { await loadLatest() }
    }

    private func loadLatest() async {
        await model.load(storyID, using: remote)
        if let story = model.detail?.story { onUpdated(story) }
    }

    private struct ArtworkLoad: Hashable {
        let artwork: OiCucumberArtworkReference?
        let cardPath: String?
        let attempt: Int
    }

    private func loadArtwork(_ reference: OiCucumberArtworkReference?, cardPath path: String?) async {
        checkedAppearance = nil; appearanceImages = [:]; checkedCard = nil; appearanceError = false
        do {
            if let reference {
                var images: [OiCucumberArtworkReference.Part: UIImage] = [:]
                for part in reference.parts {
                    images[part] = try await remote.cucumberImage(reference.path(part), part: part)
                }
                try Task.checkCancellation()
                guard artwork == reference else { return }
                appearanceImages = images; checkedAppearance = reference
            }
            if let path {
                let image = try await remote.cucumberImage(path)
                try Task.checkCancellation()
                guard cardPath == path else { return }
                checkedCard = (path, image)
            }
        } catch {
            if !Task.isCancelled, artwork == reference, cardPath == path { appearanceError = true }
        }
    }
}

struct OiOperatorStoryStatus: View {
    let status: String
    var body: some View {
        Text(status.oiStatusTitle).font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(status == "published" ? Color.green : Color.secondary)
            .background((status == "published" ? Color.green : Color.gray).opacity(0.12), in: Capsule())
    }
}
