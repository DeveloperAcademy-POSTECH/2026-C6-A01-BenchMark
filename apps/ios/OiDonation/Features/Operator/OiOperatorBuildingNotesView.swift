//
//  OiOperatorBuildingNotesView.swift
//  OiDonation
//
//  Created by Codex on 11/16/26.
//

import SwiftUI

struct OiOperatorBuildingNotesView: View {
    let remote: OiRemoteStore
    @State private var reports: [CampusBuildingNoteReport] = []
    @State private var selected: CampusBuildingNoteReport?
    @State private var busy = false
    @State private var error: String?
    @State private var hasMore = false
    @State private var offset = 0
    @State private var request = UUID()
    var body: some View {
        List {
            Text("건물 글은 등록 즉시 공개됩니다. 접수된 신고를 확인하고 글 유지 또는 삭제를 직접 결정해 주세요.").font(.footnote)
            if let error { Text(error); Button("다시 시도") { Task { await load(reset: true) } } }
            if busy { ProgressView() }
            if reports.isEmpty && !busy && error == nil { Text("접수된 신고가 없어요.") }
            ForEach(reports) { item in
                Button { selected = item } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.buildingName).font(.headline)
                        Text(item.body).lineLimit(2)
                        Text(item.status == "pending" ? "검토 대기" : "처리 완료").font(.caption)
                    }
                }
            }
            if hasMore { Button("이전 신고 더 보기") { Task { await load(reset: false) } }.disabled(busy) }
        }.navigationTitle("건물 글 신고").privacySensitive()
            .task(id: remote.account?.id) { await load(reset: true) }
            .refreshable { await load(reset: true) }
            .onDisappear { request = UUID() }
            .sheet(item: $selected, onDismiss: { Task { await load(reset: true) } }) { item in
                OiOperatorBuildingNoteDecision(remote: remote, report: item)
            }
    }
    private func load(reset: Bool) async {
        guard remote.isOperator, let owner = remote.account?.id else { reports = []; return }
        let id = UUID(); request = id; busy = true; error = nil
        defer { if request == id { busy = false } }
        let start = reset ? 0 : offset
        do {
            let page = try await remote.buildingNoteReports(offset: start)
            guard request == id, !Task.isCancelled, owner == remote.account?.id else { return }
            var ids = Set((reset ? [] : reports).map(\.id))
            reports = (reset ? [] : reports) + page.filter { ids.insert($0.id).inserted }
            offset = start + page.count; hasMore = page.count == 50
        } catch {
            guard request == id, !Task.isCancelled, owner == remote.account?.id else { return }
            self.error = error.localizedDescription
        }
    }
}

private struct OiOperatorBuildingNoteDecision: View {
    let remote: OiRemoteStore
    let report: CampusBuildingNoteReport
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var action: String?
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section(report.buildingName) {
                    Text(report.body)
                    if report.noteStatus == "deleted" { Text("이미 삭제된 글입니다.").font(.footnote) }
                }
                Section("신고 내용") {
                    Text(["abuse":"괴롭힘·혐오·모욕", "privacy":"개인정보·권리 침해", "sexual":"선정적인 내용", "violence":"폭력·위험한 내용", "other":"기타"][report.reason] ?? report.reason)
                    if !report.detail.isEmpty { Text(report.detail) }
                    if let previous = report.reviewNote { Text(previous) }
                }
                if report.status == "pending" {
                    Section("검토 결과") {
                        TextField("조치 사유 (필수, 1,000자 이내)", text: $note, axis: .vertical)
                        Button("신고 종결 · 글 유지") { action = "dismissed"; confirming = true }
                        Button("글 삭제", role: .destructive) { action = "deleted"; confirming = true }
                        if let error { Text(error).font(.footnote) }
                        if busy { ProgressView() }
                    }.disabled(busy || !remote.isOperator)
                }
            }.navigationTitle("건물 글 검토").privacySensitive()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .confirmationDialog("검토 결과를 적용할까요?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("적용", role: action == "deleted" ? .destructive : nil) { apply() }
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.unicodeScalars.count > 1000)
                    Button("취소", role: .cancel) { action = nil }
                }
                .onDisappear { task?.cancel() }
        }
    }
    private func apply() {
        guard let action, let owner = remote.account?.id, !busy else { return }
        busy = true; error = nil
        task = Task {
            defer { busy = false }
            do {
                try await remote.reviewBuildingNote(report: report.id, action: action, note: note)
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                self.error = "처리를 확인하지 못했어요. 목록을 새로고침해 상태를 확인해 주세요."
            }
        }
    }
}
