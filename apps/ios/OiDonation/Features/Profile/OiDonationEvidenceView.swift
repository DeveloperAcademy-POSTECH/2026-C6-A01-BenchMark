//
//  OiDonationEvidenceView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/5/26.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct OiDonationEvidenceView: View {
    let remote: OiRemoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private struct Attachment {
        let owner: UUID
        let data: Data
        let mime: String
        let name: String
        var fileExtension: String { mime == "application/pdf" ? "pdf" : mime == "image/png" ? "png" : "jpg" }
    }
    private enum Source { case photo(PhotosPickerItem), file(URL) }
    private struct Selection: Identifiable {
        let id = UUID()
        let owner: UUID
        let source: Source
    }
    private enum Operation { case submit(Attachment), retryUpload, analyze(OiEvidence) }
    private struct Job: Identifiable {
        let id = UUID()
        let owner: UUID
        let operation: Operation
    }
    @State private var attachment: Attachment?
    @State private var selection: Selection?
    @State private var job: Job?
    @State private var photo: PhotosPickerItem?
    @State private var pickerOwner: UUID?
    @State private var choosingSource = false
    @State private var pickingPhoto = false
    @State private var importing = false
    @State private var confirming = false
    @State private var requestedOperation: Operation?
    @State private var selectedID: UUID?
    @State private var review: OiDonationEvidenceReview?
    @State private var error: String?

    private var ownEvidence: [OiEvidence] { remote.evidence.filter { $0.userId == remote.account?.id } }
    private var selected: OiEvidence? { ownEvidence.first { $0.id == selectedID } }
    private var replacing: OiEvidence? {
        guard let selected, ["changes_requested", "rejected"].contains(selected.status) else { return nil }
        return selected
    }
    private var processing: Bool { selection != nil || job != nil }
    private var canAct: Bool { remote.account != nil && remote.hasLoadedRemote && !remote.needsReauthentication && !remote.isBusy && !processing }
    private var canRetryUpload: Bool { remote.evidenceOperation?.phase == "failed" }

    var body: some View {
        VStack(spacing: 0) {
            if remote.account == nil || remote.needsReauthentication {
                ContentUnavailableView {
                    Label("로그인이 필요해요", systemImage: "person")
                } description: { Text("본인 계정으로 기부 인증 자료를 제출해 주세요.") }
                actions: { NavigationLink("로그인하기") { MYSettingsView(remote: remote) } }
            } else if !remote.hasLoadedRemote {
                OiConnectionStatus(remote: remote)
                Spacer()
            } else {
                OiDonationEvidenceContent(evidence: ownEvidence, attachmentName: attachment?.name,
                    attachmentImage: attachment.flatMap { $0.mime == "application/pdf" ? nil : UIImage(data: $0.data) },
                    isProcessing: processing || remote.isBusy, canSubmit: canAct && attachment != nil && !canRetryUpload,
                    selectedID: selectedID, review: review, message: error,
                    onAttach: { pickerOwner = remote.account?.id; choosingSource = true },
                    onSubmit: { if let attachment { request(.submit(attachment)) } },
                    onSelect: { selectedID = $0.id; review = nil; error = nil })
                .refreshable { await remote.refresh() }
                if let loadError = remote.loadError {
                    Text(loadError).font(.footnote)
                    Button("상태 다시 확인") { Task { await remote.refresh() } }.frame(minHeight: 44)
                }
                if canRetryUpload {
                    Button("접수 중단된 자료 다시 제출") { request(.retryUpload) }
                        .disabled(!canAct).frame(minHeight: 44)
                        .accessibilityIdentifier("donation.evidence.retryUpload")
                } else if selected?.status == "pending" {
                    Button("선택한 자료 AI 검사 다시 시도") {
                        if let selected { request(.analyze(selected)) }
                    }
                        .disabled(!canAct).frame(minHeight: 44)
                        .accessibilityIdentifier("donation.evidence.retryAnalysis")
                }
            }
        }
        .background(Color.white.ignoresSafeArea()).foregroundStyle(.black)
        .navigationTitle("").navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold)) }
                    .buttonBorderShape(.circle).controlSize(.large).accessibilityLabel("뒤로")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    DonationSeedArtwork()
                    Text("\(ownEvidence.filter { $0.status == "approved" }.count)건")
                        .font(.custom("Paperlogy-7Bold", size: 20, relativeTo: .title3))
                }.padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color(red: 1, green: 254 / 255, blue: 228 / 255), in: Capsule())
                    .overlay { Capsule().stroke(Color(red: 198 / 255, green: 191 / 255, blue: 91 / 255), lineWidth: 1.5) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("작성 승인된 증빙 \(ownEvidence.filter { $0.status == "approved" }.count)건")
            }.sharedBackgroundVisibility(.hidden)
        }
        .confirmationDialog("자료 첨부", isPresented: $choosingSource, titleVisibility: .visible) {
            Button("사진 보관함") { pickingPhoto = true }
            Button("파일 선택 · JPEG / PNG / PDF") { importing = true }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png, .pdf]) { result in
            guard let owner = pickerOwner, owner == remote.account?.id else { return }
            switch result {
            case .success(let url): selection = Selection(owner: owner, source: .file(url))
            case .failure(let failure): if (failure as NSError).code != NSUserCancelledError { error = "파일을 열지 못했어요. 다시 선택해 주세요." }
            }
        }
        .onChange(of: photo) { _, value in
            guard let value, let owner = pickerOwner, owner == remote.account?.id else { return }
            selection = Selection(owner: owner, source: .photo(value))
        }
        .alert("자료 제출 및 AI 검사", isPresented: $confirming) {
            Button("동의하고 요청") { startJob() }
            Button("취소", role: .cancel) { requestedOperation = nil }
        } message: {
            Text("선택한 기부 증빙을 비공개로 제출하고 OpenAI에 전송해 시각적 수정을 검사해요. 불필요한 개인정보는 가려 주세요. AI 결과는 실제 납입이나 진위를 보증하지 않으며 글 작성은 운영자 승인 후 가능해요.")
        }
        .task(id: selection?.id) { if let selection { await load(selection) } }
        .task(id: job?.id) { if let job { await perform(job) } }
        .task(id: scenePhase) { if scenePhase == .active { await remote.refresh() } }
        .onChange(of: remote.account?.id) { _, _ in clear() }
        .onChange(of: remote.needsReauthentication) { _, required in if required { clear() } }
        .onChange(of: remote.evidence) { _, _ in
            if let review, !ownEvidence.contains(where: { $0.id == review.evidenceId && $0.submittedAt == review.submittedAt && $0.status == "pending" }) {
                self.review = nil
            }
        }
        .onDisappear { clear() }
    }

    private func clear() {
        attachment = nil; selection = nil; job = nil; photo = nil; pickerOwner = nil; requestedOperation = nil
        selectedID = nil; review = nil; error = nil
        choosingSource = false; pickingPhoto = false; importing = false; confirming = false
    }

    private func request(_ operation: Operation) {
        requestedOperation = operation
        confirming = true
    }

    private func startJob() {
        defer { requestedOperation = nil }
        guard canAct, let owner = remote.account?.id, let operation = requestedOperation else { return }
        switch operation {
        case .submit(let attachment): guard attachment.owner == owner else { return }
        case .analyze(let evidence):
            guard ownEvidence.contains(where: { $0 == evidence && $0.status == "pending" }) else { return }
        case .retryUpload: guard canRetryUpload else { return }
        }
        error = nil; review = nil
        job = Job(owner: owner, operation: operation)
    }

    private func perform(_ input: Job) async {
        defer { if job?.id == input.id { job = nil } }
        guard input.owner == remote.account?.id else { return }
        do {
            let evidence: OiEvidence
            switch input.operation {
            case .submit(let attachment):
                let previousUploadID = remote.evidenceOperation?.uploadID
                await remote.submitEvidence(data: attachment.data, contentType: attachment.mime,
                    fileExtension: attachment.fileExtension, replacing: replacing)
                guard remote.evidenceOperation?.uploadID != previousUploadID else {
                    throw OiServiceError.server(remote.error ?? "새 자료를 접수하지 못했어요. 파일을 유지했으니 다시 시도해 주세요.")
                }
                evidence = try submittedEvidence(owner: input.owner)
            case .retryUpload:
                await remote.retryEvidence()
                evidence = try submittedEvidence(owner: input.owner)
            case .analyze(let request): evidence = request
            }
            try Task.checkCancellation()
            guard job?.id == input.id, remote.account?.id == input.owner else { return }
            selectedID = evidence.id
            attachment = nil; photo = nil
            let result = try await remote.reviewDonationEvidence(evidence)
            guard !Task.isCancelled, job?.id == input.id, remote.account?.id == input.owner else { return }
            review = result
        } catch {
            guard !Task.isCancelled, job?.id == input.id, remote.account?.id == input.owner else { return }
            self.error = (error as? OiServiceError)?.localizedDescription ?? "처리를 완료하지 못했어요. 접수 상태를 확인하고 다시 시도해 주세요."
        }
    }

    private func submittedEvidence(owner: UUID) throws -> OiEvidence {
        guard remote.account?.id == owner, let operation = remote.evidenceOperation,
              operation.phase == "pending", let request = ownEvidence.first(where: { $0.id == operation.requestID }),
              request.objectPath == operation.objectPath(owner: owner) else {
            throw OiServiceError.server(remote.error ?? "자료 접수를 확인하지 못했어요. 상태를 새로 확인한 뒤 다시 시도해 주세요.")
        }
        return request
    }

    private func load(_ input: Selection) async {
        defer { if selection?.id == input.id { selection = nil; photo = nil } }
        do {
            let data: Data, mime: String, name: String
            switch input.source {
            case .photo(let item):
                guard let original = try await item.loadTransferable(type: Data.self) else { throw OiServiceError.invalidInput }
                data = try OiPhotoProcessor.prepare(original); mime = "image/jpeg"; name = "선택한 사진"
            case .file(let url):
                (data, mime) = try await Self.readFile(url); name = url.lastPathComponent
            }
            try Task.checkCancellation()
            guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw OiServiceError.invalidInput }
            guard selection?.id == input.id, remote.account?.id == input.owner else { return }
            attachment = Attachment(owner: input.owner, data: data, mime: mime, name: name)
            review = nil; error = nil
        } catch {
            guard !Task.isCancelled, selection?.id == input.id, remote.account?.id == input.owner else { return }
            self.error = "JPEG·PNG·PDF 파일을 10MB 이하로 선택해 주세요."
        }
    }

    @concurrent private static func readFile(_ url: URL) async throws -> (Data, String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let maximum = 10 * 1024 * 1024
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximum,
              let mime = values.contentType?.preferredMIMEType,
              ["image/jpeg", "image/png", "application/pdf"].contains(mime) else { throw OiServiceError.invalidInput }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, maximum + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= maximum else { throw OiServiceError.invalidInput }
        }
        guard !data.isEmpty else { throw OiServiceError.invalidInput }
        let signature: [UInt8] = mime == "application/pdf" ? [0x25, 0x50, 0x44, 0x46, 0x2d]
            : mime == "image/png" ? [137, 80, 78, 71, 13, 10, 26, 10] : [0xff, 0xd8, 0xff]
        guard data.starts(with: signature) else { throw OiServiceError.invalidInput }
        return (data, mime)
    }
}
