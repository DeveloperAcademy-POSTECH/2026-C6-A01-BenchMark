//
//  OiSchoolEvidenceView.swift
//  OiDonation
//
//  Created by 이돈혁 on 2026-11-04.
//

import SwiftUI
import UniformTypeIdentifiers

struct OiSchoolEvidenceView: View {
    let remote: OiRemoteStore

    private struct Selection: Identifiable {
        let id = UUID()
        let url: URL
        let owner: UUID
    }

    @State private var acknowledged = false
    @State private var importing = false
    @State private var selection: Selection?
    @State private var review: OiSchoolEvidenceReview?
    @State private var error: String?

    var body: some View {
        List {
            if remote.account != nil {
                Section("학교 소속 증빙") {
                    Text("학교명과 소속 표기만 남긴 학생증 사본 또는 가상 에브리타임 화면을 사용해 주세요. 이름·학번·사진·바코드·QR은 복원할 수 없게 제거해 주세요.")
                        .font(.footnote)
                    Toggle("개인정보를 제거했고 선택한 파일의 OpenAI 전송에 동의합니다", isOn: $acknowledged)
                        .disabled(selection != nil)
                    Button("증빙 파일 선택") { importing = true }
                        .disabled(!acknowledged || selection != nil)
                        .accessibilityIdentifier("oi.schoolEvidence.select")
                    Text("JPEG·PNG·PDF, 최대 10MB")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if selection != nil { ProgressView("학교 증빙 분석 중") }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if let review {
                    Section("AI 검토 결과") {
                        Text(review.assessment.verdict.title).font(.headline)
                        Text(review.assessment.readability.title)
                        Text(review.notice).font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(review.assessment.findings.enumerated()), id: \.offset) { _, finding in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(finding.location).font(.subheadline.bold())
                                Text(finding.observation)
                            }
                        }
                    }
                    Section("판독 한계") {
                        ForEach(Array(review.assessment.limitations.enumerated()), id: \.offset) { _, limitation in
                            Text(limitation)
                        }
                    }
                    Section("추가 확인 항목") {
                        ForEach(Array(review.assessment.manualChecks.enumerated()), id: \.offset) { _, check in
                            Text(check)
                        }
                    }
                }
            } else {
                Text("로그인해 주세요.")
            }
        }
        .navigationTitle("학교 인증")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png, .pdf]) { result in
            guard acknowledged, let owner = remote.account?.id else { return }
            review = nil
            error = nil
            do {
                selection = Selection(url: try result.get(), owner: owner)
                acknowledged = false
            } catch {
                self.error = "파일을 선택하지 못했어요. 파일 앱에서 다시 선택해 주세요."
            }
        }
        .task(id: selection?.id) {
            guard let selection else { return }
            await analyze(selection)
        }
        .onChange(of: remote.account?.id) { clear() }
        .onDisappear { clear() }
    }

    private func clear() {
        selection = nil
        review = nil
        error = nil
        acknowledged = false
    }

    private func analyze(_ input: Selection) async {
        defer { if selection?.id == input.id { selection = nil } }
        do {
            let (data, mime) = try await Self.readFile(input.url)
            try Task.checkCancellation()
            guard selection?.id == input.id, remote.account?.id == input.owner else { return }
            let result = try await remote.reviewSchoolEvidence(data, contentType: mime)
            guard !Task.isCancelled, selection?.id == input.id else { return }
            review = result
        } catch {
            guard !Task.isCancelled, selection?.id == input.id else { return }
            self.error = (error as? OiServiceError)?.localizedDescription
                ?? "파일이나 분석 응답을 읽지 못했어요. 파일 형식과 네트워크를 확인한 뒤 다시 시도해 주세요."
        }
    }

    @concurrent
    private static func readFile(_ url: URL) async throws -> (Data, String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let maximum = 10 * 1024 * 1024
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        let invalidFile = OiServiceError.server("JPEG·PNG·PDF 파일을 10MB 이하로 선택해 주세요.")
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximum,
              let mime = values.contentType?.preferredMIMEType,
              ["image/jpeg", "image/png", "application/pdf"].contains(mime) else { throw invalidFile }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, maximum + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= maximum else { throw invalidFile }
        }
        guard !data.isEmpty else { throw invalidFile }
        return (data, mime)
    }
}

private extension OiSchoolEvidenceReview.Assessment.Verdict {
    var title: String {
        switch self {
        case .suspicious: "의심 징후 있음"
        case .noObviousSigns: "뚜렷한 징후 없음"
        case .inconclusive: "판단 보류"
        }
    }
}

private extension OiSchoolEvidenceReview.Assessment.Readability {
    var title: String {
        switch self {
        case .readable: "판독 가능"
        case .limited: "일부 판독 가능"
        case .unreadable: "판독 불가"
        }
    }
}
