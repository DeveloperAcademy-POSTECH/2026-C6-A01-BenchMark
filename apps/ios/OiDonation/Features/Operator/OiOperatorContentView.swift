//
//  OiOperatorContentView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/6/26.
//

import SwiftUI

struct OiOperatorContentView: View {
    let remote: OiRemoteStore
    @State private var reports: [OiContentReport] = []
    @State private var selected: OiContentReport?
    @State private var error: String?
    @State private var busy = false
    @State private var hasMore = false
    @State private var offset = 0
    @State private var requestID = UUID()
    var body: some View {
        List {
            Text("신고 내용은 운영자만 볼 수 있습니다. 이메일로 받은 신고도 확인하고, 조치 사유를 기록해 주세요.").font(.footnote)
            if let error { Text(error); Button("다시 시도") { Task { await load(reset: true) } } }
            if busy { ProgressView() }
            if reports.isEmpty && !busy && error == nil { Text("접수된 신고가 없어요.") }
            ForEach(reports) { report in
                Button { selected = report } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.title).font(.headline)
                        Text(report.status == "pending" ? "검토 대기" : "처리 완료").font(.caption)
                    }
                }
            }
            if hasMore { Button("이전 신고 더 보기") { Task { await load(reset: false) } }.disabled(busy) }
        }
        .navigationTitle("콘텐츠 신고")
        .privacySensitive()
        .task(id: remote.account?.id) { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .onDisappear { requestID = UUID() }
        .sheet(item: $selected, onDismiss: { Task { await load(reset: true) } }) { report in
            OiOperatorContentDecision(remote: remote, report: report)
        }
    }

    private func load(reset: Bool) async {
        guard let owner = remote.account?.id, remote.isOperator else { reports = []; return }
        let request = UUID(); requestID = request
        busy = true; error = nil
        defer { if request == requestID { busy = false } }
        let start = reset ? 0 : offset
        do {
            let page = try await remote.contentReports(offset: start)
            guard !Task.isCancelled, requestID == request, owner == remote.account?.id else { return }
            let existing = reset ? [] : reports
            var ids = Set(existing.map(\.id))
            reports = existing + page.filter { ids.insert($0.id).inserted }
            hasMore = page.count == 50; offset = start + page.count
        } catch {
            guard !Task.isCancelled, requestID == request, owner == remote.account?.id else { return }
            self.error = "신고 목록을 읽지 못했어요. 서버 적용 상태와 운영자 권한을 확인해 주세요."
        }
    }
}

private struct OiOperatorContentDecision: View {
    let remote: OiRemoteStore
    let report: OiContentReport
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var action: String?
    @State private var confirmation = false
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("이야기") { Text(report.title).font(.headline); Text(report.body) }
                Section("신고 내용") {
                    Text(["abuse": "괴롭힘·혐오·모욕", "privacy": "개인정보·권리 침해", "sexual": "선정적인 내용", "violence": "폭력·위험한 내용", "other": "기타"][report.reason] ?? report.reason); Text(report.detail.isEmpty ? "추가 설명 없음" : report.detail)
                    if let previous = report.reviewNote { Text("기존 처리: " + previous) }
                }
                Section("운영자 조치") {
                    TextField("조치 사유 (필수, 1,000자 이내)", text: $note, axis: .vertical)
                    if let error { Text(error) }
                    if busy { ProgressView("처리 중") }
                    if report.status == "pending" {
                        decision("신고 종결 · 게시물 유지", action: "dismissed")
                        decision("이 게시물 비공개", action: "hidden")
                        decision("작성자 공개·작성 제한", action: "suspended")
                    }
                    if report.restricted { decision("작성자 제한 해제", action: "restore") }
                    Text("작성자 제한은 다른 공개 이야기도 숨기고 새 작성·공개를 막습니다. 해제해도 이 신고로 비공개한 글은 자동 공개하지 않습니다.")
                        .font(.footnote)
                }.disabled(busy)
            }
            .navigationTitle("신고 검토")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .confirmationDialog("이 조치를 적용할까요?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("적용", role: .destructive) { apply() }
                Button("취소", role: .cancel) { action = nil }
            }
            .privacySensitive()
            .onDisappear { task?.cancel() }
        }
    }
    private func decision(_ title: String, action: String) -> some View {
        Button(title) { self.action = action; confirmation = true }
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 1000)
    }
    private func apply() {
        guard let action, !busy, let owner = remote.account?.id else { return }
        busy = true; error = nil
        task = Task {
            defer { busy = false }
            do {
                try await remote.reviewContent(report: report.id, action: action, note: note)
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                self.error = "처리를 확인하지 못했어요. 목록을 새로고침해 상태를 확인해 주세요."
            }
        }
    }
}
