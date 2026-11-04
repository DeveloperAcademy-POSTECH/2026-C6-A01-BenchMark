import SwiftUI

struct OiOperatorEvidenceHistoryView: View {
    let remote: OiRemoteStore
    let evidenceID: UUID
    @State private var model = OiOperatorEvidenceHistoryModel()
    @State private var original: OiEvidenceHistory?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        List {
            Section {
                Text("상태가 변경될 때 보관된 이전 상태와 검토 의견·원본입니다. 현재 제출본과 구분해서 확인해 주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.isLoading { ProgressView("증빙 이력을 불러오는 중") }
            else if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("다시 불러오기") { Task { await model.load(evidenceID, using: remote) } }
                }
            } else if model.hasLoaded {
                if model.rows.isEmpty {
                    ContentUnavailableView("보관된 이전 상태가 없어요", systemImage: "clock.arrow.circlepath")
                } else {
                    ForEach(model.rows) { row in
                        Section {
                            LabeledContent("기록된 이전 상태", value: row.status.oiStatusTitle)
                            LabeledContent("보관 시각", value: row.recordedDateLabel)
                            if let reviewer = row.reviewerId {
                                LabeledContent("검토자", value: remote.profiles.first { $0.id == reviewer }?.nickname ?? reviewer.uuidString)
                            }
                            Text(row.reviewNote.flatMap { $0.isEmpty ? nil : $0 } ?? "기록된 검토 의견 없음")
                            Button("이 이력의 원본 열기", systemImage: "doc.text.viewfinder") { original = row }
                        }
                    }
                }
            }
        }
        .navigationTitle("증빙 상태 변경 이력").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("새로고침", systemImage: "arrow.clockwise") { Task { await model.load(evidenceID, using: remote) } }
                .disabled(model.isLoading)
        }
        .task(id: evidenceID) { await model.load(evidenceID, using: remote) }
        .refreshable { await model.load(evidenceID, using: remote) }
        .sheet(item: $original) { row in
            OiEvidenceOriginalView(remote: remote, source: .history(row), onViewed: {})
        }
        .onChange(of: phase) { _, value in if value != .active { original = nil } }
        .onChange(of: remote.account?.id) { _, _ in original = nil }
        .onChange(of: remote.isOperator) { _, allowed in if !allowed { original = nil } }
        .onChange(of: remote.needsReauthentication) { _, needed in if needed { original = nil } }
        .privacySensitive()
    }
}
