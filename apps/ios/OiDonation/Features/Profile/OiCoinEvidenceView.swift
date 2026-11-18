//
//  OiCoinEvidenceView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Figma 6101:8079. Certificate consent is independent of the story editor's skipped STEP 1.
struct OiCoinEvidenceView: View {
    let remote: OiRemoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var photo: PhotosPickerItem?
    @State private var pickerOwner: UUID?
    @State private var pickingPhoto = false
    @State private var importingFile = false
    @State private var choosingSource = false
    @State private var showingConsent = false
    @State private var confirmingCancellation = false
    @State private var upload: OiCoinEvidenceUpload?
    @State private var pendingUpload: OiCoinEvidenceUpload?
    @State private var history: [OiCoinEvidence] = []
    @State private var loading = false
    @State private var preparing = false
    @State private var error: String?
    @State private var resultMessage: String?
    @State private var work: Work?
    @State private var attachmentWork: AttachmentWork?

    private struct AttachmentWork: Identifiable {
        enum Source { case photo(PhotosPickerItem), file(URL) }
        let id = UUID()
        let owner: UUID
        let source: Source
    }

    private struct Work: Identifiable {
        let id = UUID()
        let owner: UUID
        let upload: OiCoinEvidenceUpload?
        let evidenceID: UUID?
        var cancels = false
    }

    private var busy: Bool { work != nil || preparing }

    var body: some View {
        ScrollView {
            VStack(spacing: 50) {
                OiCoinScreenHeader(remote: remote, back: { dismiss() })
                attachmentSection
                historySection
                OiCoinWalletStatus(remote: remote).padding(.horizontal, 20)
            }
            .padding(.top, 4).padding(.bottom, 32)
        }
        .background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("자료 첨부", isPresented: $choosingSource, titleVisibility: .visible) {
            Button("사진 보관함") { pickerOwner = remote.account?.id; pickingPhoto = true }
            Button("파일 선택") { pickerOwner = remote.account?.id; importingFile = true }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, value in
            guard let value, let owner = pickerOwner else { return }
            attachmentWork = AttachmentWork(owner: owner, source: .photo(value))
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.jpeg, .png, .pdf]) { result in
            guard let owner = pickerOwner else { return }
            switch result {
            case .success(let url): attachmentWork = AttachmentWork(owner: owner, source: .file(url))
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .task(id: attachmentWork?.id) {
            guard let input = attachmentWork else { return }
            preparing = true; error = nil
            defer {
                if attachmentWork?.id == input.id { preparing = false; photo = nil; attachmentWork = nil }
            }
            do {
                let data: Data
                let mime: String
                let name: String
                switch input.source {
                case .photo(let item):
                    guard let original = try await item.loadTransferable(type: Data.self) else { throw OiServiceError.invalidInput }
                    data = try OiPhotoProcessor.prepare(original); mime = "image/jpeg"; name = "선택한 사진"
                case .file(let url):
                    (data, mime) = try await Self.readFile(url); name = url.lastPathComponent
                }
                guard input.owner == remote.account?.id, !Task.isCancelled else { return }
                setAttachment(data, mime: mime, name: name, owner: input.owner)
            } catch {
                if input.owner == remote.account?.id, !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        .alert("기부 증서 AI 인증 동의", isPresented: $showingConsent) {
            Button("취소", role: .cancel) {}
            Button("동의하고 인증") {
                guard let upload, upload.owner == remote.account?.id else { return }
                pendingUpload = upload
                work = Work(owner: upload.owner, upload: upload, evidenceID: nil)
            }
        } message: {
            Text("선택한 POSTECH 기부증서 또는 기부금영수증을 비공개로 보관하고, 기부처·기부일·금액·증서번호·기부자 정보 확인과 중복 지급 방지를 위해 OpenAI에 전송합니다. 필요 없는 개인정보는 가려 주세요. AI 결과는 문서 진위나 실제 납입을 보증하지 않습니다. 확인된 서로 다른 기부마다 30pc를 한 번 지급하며, 자료는 탈퇴 시 삭제합니다.")
        }
        .alert("이 인증을 중단할까요?", isPresented: $confirmingCancellation) {
            Button("계속 인증하기", role: .cancel) {}
            Button("중단하고 다른 자료 첨부", role: .destructive) {
                guard let pendingUpload, pendingUpload.owner == remote.account?.id else { return }
                work = Work(owner: pendingUpload.owner, upload: nil, evidenceID: pendingUpload.id, cancels: true)
            }
        } message: {
            Text("아직 완료되지 않은 인증을 중단하고 이 기기의 재시도 자료를 삭제합니다. 이미 완료된 인증과 지급된 코인은 유지하며, 서버에 제출한 자료는 계정의 비공개 이력으로 보관합니다.")
        }
        .task(id: remote.account?.id) {
            upload = nil; pendingUpload = nil; history = []; error = nil; resultMessage = nil; work = nil
            attachmentWork = nil; preparing = false
            await reload()
        }
        .task(id: work?.id) {
            guard let work else { return }
            await verify(work)
        }
        .onDisappear { upload = nil; photo = nil; attachmentWork = nil; preparing = false }
        .refreshable { await reload() }
        .accessibilityIdentifier("pickle.evidence")
    }

    private var attachmentSection: some View {
        VStack(spacing: 12) {
            Button { choosingSource = true } label: {
                VStack(spacing: 10) {
                    if preparing { ProgressView("자료 준비 중") }
                    else {
                        Text(upload?.name ?? pendingUpload?.name ?? "+ 파일 첨부 하기")
                            .font(CampusStyle.semibold(24)).tracking(0.48)
                            .foregroundStyle(Color(oiRGB: 0x5D5D5D))
                        Text("이미지 또는 PDF 파일만 가능")
                            .font(CampusStyle.medium(14)).tracking(0.28)
                            .foregroundStyle(Color(oiRGB: 0xA1A1A1))
                    }
                }
                .multilineTextAlignment(.center).padding(24)
                .frame(maxWidth: .infinity, minHeight: 180)
                .background {
                    RoundedRectangle(cornerRadius: 30).fill(Color(oiRGB: 0xF3F3F3)
                        .shadow(.inner(color: Color(oiRGB: 0x797979).opacity(0.6), radius: 10)))
                }
            }
            .buttonStyle(.plain).disabled(busy || pendingUpload != nil || !remote.canVerifyCoinEvidence)
            .accessibilityIdentifier("pickle.evidence.attach")
            Group {
                if dynamicTypeSize.isAccessibilitySize { VStack(spacing: 8) { attachmentButtons } }
                else { HStack(spacing: 8) { attachmentButtons } }
            }
            if busy { ProgressView("인증 확인 중") }
            if let error { Text(error).font(CampusStyle.body(14)).foregroundStyle(.red) }
            if let resultMessage { Text(resultMessage).font(CampusStyle.body(14)).foregroundStyle(CampusStyle.green) }
            if let pendingUpload, !busy {
                Button("중단된 인증 이어하기") {
                    work = Work(owner: pendingUpload.owner, upload: pendingUpload, evidenceID: nil)
                }
                .font(CampusStyle.medium(16)).frame(minHeight: 44)
                .accessibilityIdentifier("pickle.evidence.resume")
                Button("이 인증을 중단하고 다른 자료 첨부", role: .destructive) { confirmingCancellation = true }
                    .font(CampusStyle.body(14)).frame(minHeight: 44)
                    .accessibilityIdentifier("pickle.evidence.cancelPending")
            }
        }
        .padding(.horizontal, 25)
    }

    @ViewBuilder private var attachmentButtons: some View {
        Button("파일 재첨부하기") { choosingSource = true }
            .buttonStyle(OiCoinEvidenceActionStyle(isRequest: false))
            .disabled(upload == nil || busy || pendingUpload != nil)
        Button("인증 요청") { showingConsent = true }
            .buttonStyle(OiCoinEvidenceActionStyle(isRequest: true))
            .disabled(upload == nil || busy || pendingUpload != nil || !remote.canVerifyCoinEvidence)
            .accessibilityIdentifier("pickle.evidence.submit")
    }

    private var historySection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("인증 진척도").font(CampusStyle.characterTitle(24)).tracking(0.48)
                Spacer()
                Text("\(history.count)건").font(CampusStyle.medium(20)).foregroundStyle(Color(oiRGB: 0x3E3E3E))
            }
            if loading { ProgressView("인증 내역 확인 중") }
            else if history.isEmpty {
                Text("아직 인증한 기부가 없어요.").font(CampusStyle.body(16))
                    .foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(history) { item in
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack { historyDate(item); Spacer(minLength: 8); historyStatus(item) }
                        VStack(alignment: .leading, spacing: 8) { historyDate(item); historyStatus(item) }
                    }
                    if let detail = item.detail { Text(detail).font(CampusStyle.body(13)).foregroundStyle(.secondary) }
                    if item.canRetryAnalysis {
                        Button("인증 다시 확인") {
                            guard let owner = remote.account?.id else { return }
                            work = Work(owner: owner, upload: nil, evidenceID: item.id)
                        }.disabled(busy).frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 20)
                Divider()
            }
            Text("POSTECH 기부증서 또는 기부금영수증 · 10MB 이하\n최소 기부금액은 없어요. 증서 한 건씩 첨부하고, 기부자명·기부일·기부금액·통화를 모두 확인할 수 있게 해 주세요. 증서번호가 있으면 함께 보여 주세요.")
                .font(CampusStyle.body(12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 20)
        }
        .padding(.horizontal, 20)
    }

    private func historyDate(_ item: OiCoinEvidence) -> some View {
        Text(item.dateLabel).font(CampusStyle.body(16)).tracking(0.32)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func historyStatus(_ item: OiCoinEvidence) -> some View {
        HStack(spacing: 6) {
            if item.status == "approved" {
                Image("MYProfileCoin").resizable().scaledToFit().frame(width: 24, height: 26)
            }
            Text(item.statusLabel).font(CampusStyle.body(16)).tracking(0.32)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background {
            if item.status == "approved" {
                Image("DonationApprovalBackground").resizable().clipShape(Capsule())
            } else {
                Capsule().fill(item.status == "pending" ? Color(oiRGB: 0xE7EECC) : Color(oiRGB: 0xFFC697))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.status == "approved" ? "피클코인 30개 지급 완료" : item.statusLabel)
    }

    private func setAttachment(_ data: Data, mime: String, name: String, owner: UUID) {
        guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else {
            error = "10MB 이하의 자료를 선택해 주세요."; return
        }
        upload = OiCoinEvidenceUpload(id: UUID(), uploadID: UUID(), owner: owner, data: data, contentType: mime, name: name)
        resultMessage = nil
    }

    private func reload() async {
        guard let owner = remote.account?.id, remote.canVerifyCoinEvidence else { return }
        loading = true
        defer { if remote.account?.id == owner { loading = false } }
        do {
            let pending = try await remote.pendingCoinEvidenceUpload()
            let rows = try await remote.coinEvidenceHistory()
            guard remote.account?.id == owner, !Task.isCancelled else { return }
            pendingUpload = pending; history = rows
        } catch { if remote.account?.id == owner, !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func verify(_ input: Work) async {
        defer { if work?.id == input.id { work = nil } }
        do {
            if input.cancels, let id = input.evidenceID {
                let receipt = try await remote.cancelCoinEvidence(id)
                guard remote.account?.id == input.owner, !Task.isCancelled else { return }
                pendingUpload = nil; upload = nil; error = nil
                resultMessage = receipt.request.status == "approved"
                    ? "이미 인증이 완료된 자료예요. 지급된 코인은 유지되며 다른 자료를 첨부할 수 있어요."
                    : "인증을 중단했어요. 다른 자료를 첨부해 주세요."
                await reload()
                choosingSource = true
                return
            }
            let result: OiCoinEvidenceReceipt
            if let upload = input.upload { result = try await remote.verifyCoinEvidence(upload) }
            else if let evidenceID = input.evidenceID { result = try await remote.retryCoinEvidence(evidenceID) }
            else { throw OiServiceError.invalidInput }
            guard remote.account?.id == input.owner, !Task.isCancelled else { return }
            pendingUpload = nil; upload = nil; error = nil
            resultMessage = result.credited ? "기부 인증 완료! 30pc를 받았어요."
                : result.request.detail ?? "인증 결과를 확인했어요."
            await reload()
        } catch {
            if remote.account?.id == input.owner, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    @concurrent private static func readFile(_ url: URL) async throws -> (Data, String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 10 * 1024 * 1024,
              let mime = values.contentType?.preferredMIMEType,
              ["image/jpeg", "image/png", "application/pdf"].contains(mime) else { throw OiServiceError.invalidInput }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let valid = mime == "application/pdf" ? data.starts(with: Data("%PDF-".utf8))
            : mime == "image/png" ? data.starts(with: [137,80,78,71,13,10,26,10])
            : data.starts(with: [255,216,255])
        guard valid, !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw OiServiceError.invalidInput }
        return (data, mime)
    }
}


/// Figma 3739:3608–3611. The visual capsule is 42pt; its complete touch area is at least 44pt.
private struct OiCoinEvidenceActionStyle: ButtonStyle {
    let isRequest: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CampusStyle.medium(16)).tracking(0.32)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isEnabled ? Color(oiRGB: isRequest ? 0xF7FAEF : 0x708C40) : Color(oiRGB: 0xD3DBC4))
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                Capsule().fill(isEnabled ? Color(oiRGB: isRequest ? 0xB0C85B : 0xD3DBC4) : Color(oiRGB: 0xF1F4EC))
                    .padding(.vertical, 1)
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
