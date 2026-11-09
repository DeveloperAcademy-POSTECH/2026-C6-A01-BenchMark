import SwiftUI

struct OiOperatorEvidenceAnalysisSection: View {
    let remote: OiRemoteStore
    let snapshot: OiEvidence
    let blocked: Bool
    @State private var model = OiOperatorEvidenceAnalysisModel()
    @State private var analysisTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Section("AI 참고 분석") {
            Text("원본 진위나 실제 납입을 보증하지 않으며, 작성 권한을 자동 승인하지 않습니다.")
                .font(.footnote).foregroundStyle(.secondary)
            if snapshot.status == "pending" && snapshot.hasOperatorAIConsent {
                Text("분석을 요청하면 현재 증빙 원본을 기존 서버를 통해 OpenAI로 보냅니다. 결과는 이 화면에서만 확인하며 자동으로 재요청하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                if model.isLoading {
                    ProgressView("현재 제출본을 분석하는 중")
                    Button("분석 요청 취소") { clear() }
                } else {
                    Button(model.error == nil && model.result == nil ? "현재 제출본 분석 요청" : "직접 다시 분석 요청",
                           systemImage: "sparkle.magnifyingglass") {
                        analysisTask = Task { await model.analyze(snapshot, using: remote) }
                    }
                    .disabled(blocked || remote.isBusy || !remote.isOperator || remote.needsReauthentication || phase != .active)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                    Text("실패한 분석에는 판정 결과가 없습니다. 최신 증빙을 확인하거나 원본을 직접 검토해 주세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let result = model.result { OiEvidenceAnalysisResultView(result: result) }
            } else if snapshot.status == "pending" {
                Text("이 제출본의 AI 분석 동의가 확인되지 않았어요. 원본을 직접 검토해 주세요.")
                    .foregroundStyle(.secondary)
            } else {
                Text("AI 분석은 검토 대기 중인 현재 제출본에만 제공됩니다.").foregroundStyle(.secondary)
            }
        }
        .task(id: model.result?.analyzedAt) {
            guard model.result != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await model.revalidate(snapshot, using: remote)
                if model.result == nil { return }
            }
        }
        .onChange(of: snapshot) { _, _ in clear() }
        .onChange(of: blocked) { _, value in if value { clear() } }
        .onChange(of: remote.revision) { _, _ in
            if remote.evidence.first(where: { $0.id == snapshot.id }) != snapshot { clear() }
        }
        .onChange(of: phase) { _, value in if value != .active { clear() } }
        .onChange(of: remote.account?.id) { _, _ in clear() }
        .onChange(of: remote.isOperator) { _, allowed in if !allowed { clear() } }
        .onChange(of: remote.needsReauthentication) { _, needed in if needed { clear() } }
        .onDisappear { clear() }
        .privacySensitive()
    }

    private func clear() { analysisTask?.cancel(); analysisTask = nil; model.invalidate() }
}

struct OiEvidenceAnalysisResultView: View {
    let result: OiEvidenceAnalysis
    var body: some View {
        LabeledContent("참고 결과", value: result.assessment.verdict.title)
        LabeledContent("판독 상태", value: result.assessment.readability.title)
        LabeledContent("분석 대상 제출 시각", value: OiEvidence.dateLabel(result.submittedAt))
        LabeledContent("분석 시각", value: OiEvidence.dateLabel(result.analyzedAt))
        Text(result.notice).font(.footnote).foregroundStyle(.secondary)
        if result.assessment.findings.isEmpty {
            Text("보고된 의심 징후 없음 · 원본 진위 인증이 아닙니다.")
        } else {
            ForEach(Array(result.assessment.findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading, spacing: 5) {
                    Text(finding.category == .visualEdit ? "시각적 편집 징후" : "문서 내부 불일치").font(.headline)
                    Text("위치: \(finding.location)")
                    Text(finding.observation)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("분석 한계").font(.headline)
            ForEach(Array(result.assessment.limitations.enumerated()), id: \.offset) { _, text in Text("• \(text)") }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("운영자 확인 사항").font(.headline)
            ForEach(Array(result.assessment.manualChecks.enumerated()), id: \.offset) { _, text in Text("• \(text)") }
        }
    }
}
