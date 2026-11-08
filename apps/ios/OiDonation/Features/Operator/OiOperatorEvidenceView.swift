import SwiftUI
import ImageIO
import PDFKit

struct OiOperatorEvidenceListView: View {
    let remote: OiRemoteStore
    @State private var model = OiOperatorEvidenceListModel()
    @State private var selected: Selection?
    private struct Selection: Identifiable, Hashable { let id: UUID }
    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Picker("증빙 상태", selection: $model.filter) {
                    ForEach(OiEvidenceFilter.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
            }
            if model.isLoading { ProgressView("제출된 증빙을 불러오는 중") }
            else if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("다시 불러오기") { Task { await model.load(using: remote) } }
                }
            } else if model.hasLoaded {
                if model.filtered.isEmpty {
                    ContentUnavailableView("\(model.filter.title) 증빙이 없어요", systemImage: "doc.text.magnifyingglass")
                } else {
                    Section("\(model.filter.title) · \(model.filtered.count)건") {
                        ForEach(model.filtered) { row in
                            Button { selected = Selection(id: row.id) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("증빙 \(row.id.uuidString.prefix(8))").font(.headline)
                                    Text(row.status.oiStatusTitle).font(.subheadline)
                                    Text(row.submittedDateLabel).font(.caption).foregroundStyle(.secondary)
                                }.foregroundStyle(.primary).padding(.vertical, 6)
                            }.accessibilityIdentifier("operator.evidence.row.\(row.id)")
                        }
                    }
                }
            }
        }
        .navigationTitle("기부 증빙 검토").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("새로고침", systemImage: "arrow.clockwise") { Task { await model.load(using: remote) } }
                .disabled(model.isLoading || remote.isBusy)
        }
        .task { await model.load(using: remote) }
        .refreshable { await model.load(using: remote) }
        .navigationDestination(item: $selected) { value in
            OiOperatorEvidenceDetailView(remote: remote, evidenceID: value.id) { model.apply($0) }
        }
        .privacySensitive()
    }
}

struct OiOperatorEvidenceDetailView: View {
    let remote: OiRemoteStore
    let evidenceID: UUID
    var onUpdated: (OiEvidence) -> Void = { _ in }
    @State private var model = OiOperatorEvidenceModel()
    @State private var decision: OiEvidenceDecision = .approved
    @State private var note = ""
    @State private var inputError: String?
    @State private var original: OiEvidence?
    @State private var viewed: OiEvidence?
    @State private var confirmation: OiEvidenceReview?
    @State private var showingConfirmation = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        List {
            if model.isLoading { ProgressView("증빙 정보를 확인하는 중") }
            if let notice = model.notice {
                Section { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let warning = model.warning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if let row = model.detail?.evidence {
                Section("제출 정보") {
                    LabeledContent("상태", value: row.status.oiStatusTitle)
                    LabeledContent("접수 번호", value: row.id.uuidString)
                    LabeledContent("제출자", value: remote.profiles.first { $0.id == row.userId }?.nickname ?? "제출자 정보 없음")
                    LabeledContent("제출 시각", value: row.submittedDateLabel)
                    if row.reviewedAt != nil { LabeledContent("검토 시각", value: row.reviewedDateLabel) }
                    if let note = row.reviewNote, !note.isEmpty { Text("검토 의견: \(note)") }
                    ForEach(model.detail?.grants ?? []) { grant in
                        LabeledContent("이전 작성 승인 기록", value: "\(grant.storyLimit)개 · \(grant.revokedAt == nil ? "기록 보관" : "철회 기록")")
                    }
                }
                Section("비공개 증빙 원본") {
                    Button("원본 열기", systemImage: "doc.text.viewfinder") { original = row }
                        .disabled(model.isProcessing || model.isLoading || phase != .active)
                    Text(viewed == row ? "현재 제출 원본을 확인했어요." : "원본을 열고 내용을 확인한 후 검토해 주세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("증빙 상태 변경 이력") {
                        OiOperatorEvidenceHistoryView(remote: remote, evidenceID: row.id)
                    }
                }
                OiOperatorEvidenceAnalysisSection(remote: remote, snapshot: row,
                                                  blocked: model.isProcessing || model.requiresReload)
                if ["pending", "approved"].contains(row.status) {
                    Section("증빙 검토") {
                        if row.status == "pending" {
                            Picker("처리", selection: $decision) {
                                ForEach([OiEvidenceDecision.approved, .changesRequested, .rejected]) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu)
                        }
                        TextField("검토 의견 (보완·반려·철회 시 필수)", text: $note, axis: .vertical).lineLimit(3...8)
                        if let inputError { Text(inputError).foregroundStyle(.red) }
                        if model.isProcessing { ProgressView("검토 결과를 처리하는 중") }
                        Button(row.status == "approved" ? "검토 결과 철회" : "검토 결과 확인") {
                            do {
                                confirmation = try OiEvidenceReview(snapshot: row, decision: row.status == "approved" ? .revoked : decision,
                                                                    note: note)
                                inputError = nil; showingConfirmation = true
                            } catch { inputError = error.localizedDescription }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canReview || viewed != row || remote.isBusy || !remote.isOperator || remote.needsReauthentication || phase != .active)
                    }.disabled(model.isProcessing)
                }
            }
            if model.requiresReload && !model.isLoading {
                Section { Button("최신 상태 다시 불러오기") { Task { await load() } }.disabled(model.isProcessing || remote.isBusy) }
            }
            Section {
                Text("이 화면은 기부 자료의 검토 결과를 기록해요. 이야기 공개는 콘텐츠 검토에서, 공식 납입 확인과 영수증 발급은 학교에서 처리해요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("증빙 검토 상세").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("새로고침", systemImage: "arrow.clockwise") { Task { await load() } }
                .disabled(model.isLoading || model.isProcessing || remote.isBusy)
        }
        .task(id: evidenceID) { await load() }
        .refreshable { await load() }
        .sheet(item: $original) { row in
            OiEvidenceOriginalView(remote: remote, source: .submission(row)) { viewed = row }
        }
        .confirmationDialog("검토 결과를 저장할까요?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            if let review = confirmation {
                Button("\(review.decision.title) 확정", role: review.decision == .revoked ? .destructive : nil) {
                    Task {
                        guard phase == .active else { return }
                        if let saved = await model.review(review, using: remote) { onUpdated(saved); note = "" }
                        viewed = nil; confirmation = nil
                    }
                }
            }
            Button("취소", role: .cancel) { confirmation = nil }
        } message: {
            if let review = confirmation {
                Text("‘\(review.decision.title)’ 상태와 검토 의견을 저장합니다.")
            }
        }
        .onChange(of: phase) { _, value in if value != .active { clearPrivateState() } }
        .onChange(of: remote.account?.id) { _, _ in clearPrivateState() }
        .onChange(of: remote.isOperator) { _, allowed in if !allowed { clearPrivateState() } }
        .onChange(of: remote.needsReauthentication) { _, needed in if needed { clearPrivateState() } }
        .interactiveDismissDisabled(model.isProcessing)
        .privacySensitive()
    }

    private func clearPrivateState() {
        original = nil; viewed = nil; confirmation = nil; showingConfirmation = false
    }
    private func load() async {
        guard !model.isProcessing else { return }
        clearPrivateState(); inputError = nil; note = ""; decision = .approved
        await model.load(evidenceID, using: remote)
        if let row = model.detail?.evidence { onUpdated(row) }
    }
}

enum OiEvidenceOriginalSource {
    case submission(OiEvidence), history(OiEvidenceHistory)
}

struct OiEvidenceOriginalView: View {
    let remote: OiRemoteStore
    let source: OiEvidenceOriginalSource
    let onViewed: () -> Void
    @State private var document: OiEvidenceDocument?
    @State private var error: String?
    @State private var loading = true
    @State private var retry = UUID()
    @State private var owner: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    OiEvidencePreview(document: document)
                } else if loading { ProgressView("비공개 원본을 불러오는 중") }
                else {
                    ContentUnavailableView {
                        Label("원본을 열지 못했어요", systemImage: "doc.questionmark")
                    } description: { Text(error ?? "다시 확인해 주세요.") }
                    actions: { Button("다시 시도") { retry = UUID() } }
                }
            }
            .navigationTitle("비공개 증빙 원본").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if case .submission = source {
                        Button("원본 확인 완료") { onViewed(); dismiss() }.disabled(document == nil || phase != .active)
                    }
                }
            }
        }
        .task(id: retry) {
            owner = remote.account?.id
            document = nil; error = nil; loading = true
            defer { loading = false }
            do {
                let result: OiEvidenceDocument
                switch source {
                case .submission(let snapshot): result = try await remote.operatorEvidenceDocument(snapshot)
                case .history(let snapshot): result = try await remote.operatorEvidenceHistoryDocument(snapshot)
                }
                try Task.checkCancellation()
                guard phase == .active, owner == remote.account?.id, remote.isOperator, !remote.needsReauthentication else { return }
                // Validate that the renderer can actually open the bytes before enabling confirmation.
                if result.kind == .pdf {
                    guard let pdf = PDFDocument(data: result.data), !pdf.isEncrypted, pdf.pageCount > 0 else { throw OiEvidenceReviewError.invalidDocument }
                } else if OiEvidencePreview.image(result.data) == nil { throw OiEvidenceReviewError.invalidDocument }
                document = result
            } catch { if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription } }
        }
        .onChange(of: phase) { _, value in if value != .active { document = nil; dismiss() } }
        .onChange(of: remote.account?.id) { _, _ in document = nil; dismiss() }
        .onChange(of: remote.isOperator) { _, allowed in if !allowed { document = nil; dismiss() } }
        .onChange(of: remote.needsReauthentication) { _, needed in if needed { document = nil; dismiss() } }
        .onDisappear { document = nil }
        .privacySensitive()
    }
}

private struct OiEvidencePreview: View {
    let document: OiEvidenceDocument
    var body: some View {
        if document.kind == .pdf { OiEvidencePDF(data: document.data) }
        else if let image = Self.image(document.data) {
            ScrollView([.vertical, .horizontal]) {
                Image(uiImage: image).resizable().scaledToFit().frame(width: max(320, image.size.width))
                    .accessibilityLabel("제출된 증빙 원본 이미지")
            }
        }
    }
    static func image(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct OiEvidencePDF: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
    static func dismantleUIView(_ uiView: PDFView, coordinator: ()) { uiView.document = nil }
}
