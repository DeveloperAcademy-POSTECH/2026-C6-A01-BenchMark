// Created by 이돈혁

import SwiftUI
import UniformTypeIdentifiers

struct OiAccountView: View {
    let remote: OiRemoteStore
    @State private var nickname = ""
    @State private var importingEvidence = false
    @State private var fileError: String?
    @State private var replacingEvidence: OiEvidence?
    @State private var localDrafts: [OiLocalDraft] = []

    var body: some View {
        List {
            OiConnectionStatus(remote: remote)
            if let error = remote.error ?? fileError {
                Section { Text(error).foregroundStyle(.red); Button("다시 불러오기") { Task { await remote.refresh() } } }
            }
            if let account = remote.account {
                Section("내 계정") {
                    Text(account.email ?? "Google 계정")
                    Text("계정 ID: \(account.id.uuidString)").font(.caption).textSelection(.enabled)
                    TextField("농부 닉네임", text: $nickname).textInputAutocapitalization(.never)
                        .onAppear { nickname = remote.profile?.nickname ?? "농부" }
                    Button("닉네임 저장") { Task { await remote.updateProfile(nickname: nickname) } }
                        .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nickname.count > 30)
                    Button("로그아웃", role: .destructive) { Task { await remote.signOut() } }
                }
                Section("기부 증빙 · 작성 승인") {
                    Text("현재는 개발 검증용 가상 자료만 제출해 주세요. 실제 증빙 인정 기준·수집 항목·보관 기간은 아직 확정되지 않았습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("운영자 검토 후 글 작성 권한을 승인합니다. 학교 공식 납입 확인이나 영수증 발급과는 다릅니다.")
                        .font(.footnote)
                    Button("가상 증빙 제출 (JPEG·PNG·PDF, 10MB 이하)") { replacingEvidence = nil; importingEvidence = true }
                        .accessibilityIdentifier("oi.evidence.upload")
                    ForEach(remote.evidence.filter { $0.userId == account.id }) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.status.oiStatusTitle)
                            if let note = request.reviewNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                            if ["changes_requested","rejected"].contains(request.status) {
                                Button("이 신청 보완·재제출") { replacingEvidence = request; importingEvidence = true }
                            }
                        }
                    }
                    if let operation = remote.evidenceOperation {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("기기 제출 기록: \(evidencePhase(operation.phase))").font(.caption)
                            if let failure = operation.failure { Text("이전 시도: \(failure)").font(.caption).foregroundStyle(.secondary) }
                            if ["failed","prepared","uploading","submitting"].contains(operation.phase) {
                                Button("같은 신청·파일로 이어서 제출") { Task { await remote.retryEvidence() } }
                            }
                        }
                    }
                }
                Section("이 계정의 기기 초안·보관본") {
                    ForEach(localDrafts) { record in
                        NavigationLink { OiStoryEditor(remote: remote, localID: record.id) } label: {
                            VStack(alignment: .leading) {
                                Text(record.draft.title.isEmpty ? "제목 없는 초안" : record.draft.title)
                                Text(record.submitted ? "검토 요청 완료 · 기기 보관본" : "미완료 초안 · 사진 \(record.photos.count)장").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("내 이야기와 오이") {
                    NavigationLink("이야기 리스트") {
                        OiStoryListScreen(remote: remote)
                    }
                    .accessibilityIdentifier("oi.story.list")
                    if remote.grants.contains(where: { $0.revokedAt == nil }) {
                        NavigationLink("오이 만들기") { OiStoryEditor(remote: remote) }
                            .accessibilityIdentifier("oi.story.create")
                    } else {
                        Text("증빙 검토와 작성 승인이 필요해요.").foregroundStyle(.secondary)
                    }
                    if remote.ownStories.isEmpty { Text("등록한 이야기가 없어요.").foregroundStyle(.secondary) }
                    ForEach(remote.ownStories) { story in
                        NavigationLink { OiStoryManagement(remote: remote, storyID: story.id) } label: {
                            VStack(alignment: .leading) { Text(story.title); Text(story.status.oiStatusTitle).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Text("피클코인 구매·적립·사용은 비활성화돼 있어요.").font(.footnote).foregroundStyle(.secondary)
                }
                if remote.isOperator {
                    Section("운영자") { NavigationLink("증빙·이야기 검토") { OiOperatorView(remote: remote) } }
                }
            } else {
                Section {
                    Text("로그인하면 수집한 오이와 즐겨찾기, 내 이야기가 계정에 저장됩니다.")
                    Button("Google로 로그인") { Task { await remote.signIn() } }
                        .disabled(!remote.isConfigured).accessibilityIdentifier("oi.auth.google")
                    if !remote.isConfigured { Text(OiServiceError.configuration.localizedDescription).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section("아직 준비 중인 부분") {
                Text("옷·모자·하의의 개별 꾸미기, 성장·보상, 물리적 방문 인증과 AR 수집 게임 규칙은 미정입니다. 준비된 오이·카드 프리셋만 선택할 수 있어요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("계정과 내 이야기").navigationBarTitleDisplayMode(.inline)
        .onChange(of: remote.profile?.nickname) { _, value in if let value { nickname = value } }
        .disabled(remote.isBusy)
        .overlay { if remote.isBusy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .refreshable { await remote.refresh() }
        .task(id: remote.account?.id) {
            do { localDrafts = try await remote.localDrafts() }
            catch { fileError = error.localizedDescription }
        }
        .fileImporter(isPresented: $importingEvidence, allowedContentTypes: [.jpeg,.png,.pdf]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let attributes = try url.resourceValues(forKeys: [.fileSizeKey,.contentTypeKey])
                guard let size = attributes.fileSize, size > 0, size <= 10_485_760,
                      let type = attributes.contentType,
                      let mime = type.preferredMIMEType, let ext = type.preferredFilenameExtension,
                      ["image/jpeg","image/png","application/pdf"].contains(mime) else {
                    throw OiServiceError.server("JPEG·PNG·PDF 파일을 10MB 이하로 선택해 주세요.")
                }
                let data = try Data(contentsOf: url)
                fileError = nil
                let request = replacingEvidence
                Task { await remote.submitEvidence(data: data, contentType: mime, fileExtension: ext, replacing: request) }
            } catch { fileError = error.localizedDescription }
        }
    }

    private func evidencePhase(_ phase: String) -> String {
        switch phase {
        case "prepared": "파일을 기기에 보관했어요"
        case "uploading": remote.isBusy ? "파일 업로드 중" : "업로드 중단 가능 · 이어서 제출 필요"
        case "submitting": remote.isBusy ? "서버 제출 확인 중" : "제출 응답 확인 필요 · 같은 신청으로 재시도"
        case "failed": "제출 미확인 · 파일과 신청 ID 보관 중"
        default: phase.oiStatusTitle
        }
    }
}

struct OiStoryManagement: View {
    let remote: OiRemoteStore
    let storyID: UUID
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let story = remote.ownStories.first(where: { $0.id == storyID }) {
                List {
                    Text(story.title).font(.headline)
                    Text(story.status.oiStatusTitle)
                    Text(story.body)
                    if let error = remote.error { Text(error).foregroundStyle(.red) }
                    if story.status == "draft" {
                        NavigationLink("초안 수정·미리보기·검토 요청") { OiStoryEditor(remote: remote, story: story) }
                    } else {
                        Text("수정을 시작하면 공개가 해제되고 다시 검토를 요청해야 합니다.").font(.footnote)
                        Button("수정 시작") { Task { await remote.perform("reopen_story", payload: ["id":story.id.uuidString,"revision":story.revision]) } }
                    }
                    Button("이야기 삭제", role: .destructive) { confirmingDelete = true }
                    Text("삭제해도 작성 승인 수량이 자동으로 복구되지는 않습니다.").font(.footnote).foregroundStyle(.secondary)
                }
                .confirmationDialog("이야기를 비공개·삭제 상태로 바꿀까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("삭제", role: .destructive) { Task { await remote.perform("delete_story", payload: ["id":story.id.uuidString,"revision":story.revision]) } }
                }
            } else { ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc") }
        }.navigationTitle("내 이야기").navigationBarTitleDisplayMode(.inline).disabled(remote.isBusy)
    }
}

private struct OiOperatorView: View {
    let remote: OiRemoteStore
    @State private var approvedCounts: [UUID: String] = [:]
    @State private var reviewNotes: [UUID: String] = [:]

    var body: some View {
        List {
            if let error = remote.error { Text(error).foregroundStyle(.red) }
            Section("증빙 검토") {
                ForEach(remote.evidence.filter { $0.status == "pending" || $0.status == "approved" }) { request in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(request.userId.uuidString).font(.caption).textSelection(.enabled)
                        Text(request.status.oiStatusTitle)
                        if let path = request.objectPath { OiEvidenceLink(remote: remote, path: path) }
                        TextField("검토 메모", text: Binding(get: { reviewNotes[request.id] ?? "" }, set: { reviewNotes[request.id] = $0 }))
                        if request.status == "pending" {
                            TextField("승인할 글 수량 (운영자 결정)", text: Binding(get: { approvedCounts[request.id] ?? "" }, set: { approvedCounts[request.id] = $0 })).keyboardType(.numberPad)
                            Button("작성 승인") { review(request, status: "approved") }
                                .disabled((Int(approvedCounts[request.id] ?? "") ?? 0) < 1)
                            Button("보완 요청") { review(request, status: "changes_requested") }
                            Button("반려") { review(request, status: "rejected") }
                        } else {
                            Button("작성 승인 취소", role: .destructive) { review(request, status: "revoked") }
                        }
                    }.padding(.vertical, 8)
                }
            }
            Section("이야기 공개 검토") {
                ForEach(remote.reviewStories) { story in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(story.title).font(.headline)
                        Text(story.body)
                        Text(story.status.oiStatusTitle).font(.caption)
                        Text("\(story.latitude), \(story.longitude)").font(.caption)
                        ForEach(remote.media.filter { $0.storyId == story.id }) { media in
                            OiStoryMediaImage(path: media.objectPath) { path in try await remote.mediaURL(bucket: "oi-story-media", path: path) }
                                .frame(height: 140)
                        }
                        Button(story.status == "published" ? "비공개로 변경" : "공개 승인") {
                            Task { await remote.perform("review_story", payload: ["id":story.id.uuidString,"revision":story.revision,"status":story.status == "published" ? "hidden" : "published"]) }
                        }
                    }
                }
            }
        }.navigationTitle("운영자 검토").disabled(remote.isBusy).refreshable { await remote.refresh() }
    }

    private func review(_ request: OiEvidence, status: String) {
        var payload: [String: Any] = ["id":request.id.uuidString,"status":status,"review_note":reviewNotes[request.id] ?? ""]
        if let count = Int(approvedCounts[request.id] ?? "") { payload["story_limit"] = count }
        Task { await remote.perform("review_evidence", payload: payload) }
    }
}

private struct OiEvidenceLink: View {
    let remote: OiRemoteStore
    let path: String
    @State private var url: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading) {
            if let url { Link("비공개 증빙 보기 (5분 유효)", destination: url) }
            Button(url == nil ? "증빙 보기 링크 발급" : "만료된 증빙 링크 다시 발급") {
                Task { do { url = try await remote.mediaURL(bucket: "oi-evidence", path: path); error = nil } catch { self.error = error.localizedDescription } }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
