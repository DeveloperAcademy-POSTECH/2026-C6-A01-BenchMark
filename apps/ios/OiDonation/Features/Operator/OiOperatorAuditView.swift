import SwiftUI

struct OiOperatorAuditView: View {
    let remote: OiRemoteStore
    @State private var model = OiOperatorAuditModel()
    @State private var from = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var through = Date()
    @State private var category: OiAuditCategory = .all
    @State private var inputError: String?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        List {
            Section("조회 조건") {
                DatePicker("시작일", selection: $from, in: ...Date(), displayedComponents: .date)
                DatePicker("종료일", selection: $through, in: ...Date(), displayedComponents: .date)
                Picker("처리 종류", selection: $category) {
                    ForEach(OiAuditCategory.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                Text("한 번에 최대 31일을 조회합니다. 날짜와 종류를 바꾼 뒤 조회를 눌러 주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let inputError { Text(inputError).foregroundStyle(.red) }
                Button("조회") { Task { await reload() } }.disabled(model.isLoading)
            }
            if let query = model.query {
                Section {
                    Text("조회 결과: \(query.from.formatted(date: .numeric, time: .omitted)) ~ \(query.until.addingTimeInterval(-1).formatted(date: .numeric, time: .omitted)) · \(query.category.title)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button(model.hasLoaded ? "이전 기록 다시 불러오기" : "다시 조회") {
                        Task {
                            if model.hasLoaded { await model.loadMore(using: remote) }
                            else { await reload() }
                        }
                    }.disabled(model.isLoading)
                }
            }
            if model.hasLoaded && model.records.isEmpty {
                ContentUnavailableView("조회 기간에 기록이 없어요", systemImage: "clock.arrow.circlepath",
                                       description: Text("다른 날짜나 처리 종류로 조회해 주세요."))
            }
            ForEach(model.records) { record in
                Section {
                    Text(record.title).font(.headline)
                    LabeledContent("처리 시각", value: OiEvidence.dateLabel(record.createdAt))
                    LabeledContent("처리자", value: remote.profiles.first { $0.id == record.actorId }?.nickname ?? record.actorId.uuidString)
                    LabeledContent(record.targetLabel, value: record.targetId.uuidString)
                    LabeledContent("기록 번호", value: record.id)
                    if record.action == "review_story" {
                        Text("이 기록에는 당시 공개·비공개 결정값이 저장되지 않습니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if model.isLoading { ProgressView("감사 기록을 불러오는 중") }
            else if model.nextCursor != nil && model.error == nil {
                Button("이전 기록 더 보기") { Task { await model.loadMore(using: remote) } }
            }
            Section {
                Text("서버가 보관한 처리 기록입니다. 학교 공식 납입 확인이나 영수증 발급 내역이 아닙니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("운영 감사 기록").navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: phase) { _, value in if value != .active { model.invalidate() } }
        .onChange(of: remote.account?.id) { _, _ in model.invalidate() }
        .onChange(of: remote.isOperator) { _, allowed in if !allowed { model.invalidate() } }
        .onChange(of: remote.needsReauthentication) { _, needed in if needed { model.invalidate() } }
        .onDisappear { model.invalidate() }
        .privacySensitive()
    }

    private func reload() async {
        do {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: from)
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)) else { throw OiAuditError.invalidQuery }
            let query = try OiAuditQuery(from: start, until: end, category: category)
            inputError = nil
            await model.reload(query, using: remote)
        } catch { inputError = error.localizedDescription }
    }
}
