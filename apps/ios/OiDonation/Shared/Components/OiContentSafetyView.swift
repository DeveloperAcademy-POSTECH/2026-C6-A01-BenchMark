//
//  OiContentSafetyView.swift
//  OiDonation / OiDonationClip
//
//  Created by 이돈혁 on 11/6/26.
//

import SwiftUI
import UIKit

struct OiContentSafetyView: View {
    let storyID: UUID
    let authorID: UUID
    let authorName: String
    var submit: ((String, String) async throws -> String)? = nil
    var onBlock: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reason = "abuse"
    @State private var detail = ""
    @State private var busy = false
    @State private var notice: String?
    @State private var task: Task<Void, Never>?
    private let reasons = [("abuse", "괴롭힘·혐오·모욕"), ("privacy", "개인정보·권리 침해"),
                           ("sexual", "선정적인 내용"), ("violence", "폭력·위험한 내용"), ("other", "기타")]
    private let email = "8enchMark666@gmail.com"

    var body: some View {
        NavigationStack {
            Form {
                Section("이야기 신고") {
                    Picker("신고 사유", selection: $reason) {
                        ForEach(reasons, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    TextField("추가 설명 (선택, 1,000자 이내)", text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                    Text("증빙·비밀번호·연락처 등 개인정보를 적지 마세요. 운영팀이 내용을 검토해 조치합니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let notice { Text(notice).accessibilityIdentifier("content.report.notice") }
                    if busy { ProgressView("신고 접수 중") }
                    Button(submit == nil ? "이메일로 신고 작성" : "운영팀에 신고 접수") {
                        if let submit {
                            busy = true; notice = nil
                            task = Task {
                                defer { busy = false }
                                do {
                                    let status = try await submit(reason, detail)
                                    guard !Task.isCancelled else { return }
                                    notice = status == "pending" ? "신고가 접수됐어요. 운영팀이 검토합니다." : "이미 접수·처리한 신고입니다. 추가 문의는 운영팀 이메일을 이용해 주세요."
                                } catch {
                                    guard !Task.isCancelled else { return }
                                    notice = "신고를 접수하지 못했어요. 다시 시도하거나 이메일로 문의해 주세요."
                                }
                            }
                        } else { emailReport() }
                    }.disabled(busy || detail.count > 1000)
                    if submit != nil { Button("이메일로 신고 작성", action: emailReport) }
                    Text(email).textSelection(.enabled)
                    Button("문의 주소 복사") { UIPasteboard.general.string = email }
                    Button("이야기 ID 복사") { UIPasteboard.general.string = storyID.uuidString }
                }
                Section("작성자 차단") {
                    Text("이 기기의 본 앱과 App Clip에서 이 작성자의 공개 이야기를 숨깁니다. 차단은 운영팀 신고나 계정 제재와 별개이며, 차단 관리에서 해제할 수 있어요.")
                        .font(.footnote)
                    Button("이 작성자 차단", role: .destructive) {
                        if OiContentSafetyStore.shared.setBlocked(authorID, name: authorName, blocked: true) {
                            task?.cancel(); dismiss(); onBlock()
                        } else { notice = OiContentSafetyStore.shared.error }
                    }.disabled(busy)
                }
            }
            .navigationTitle("신고 및 차단")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .onDisappear { task?.cancel() }
        }
    }

    private func emailReport() {
        var url = URLComponents()
        url.scheme = "mailto"; url.path = email
        url.queryItems = [URLQueryItem(name: "subject", value: "오이기부 콘텐츠 신고"),
            URLQueryItem(name: "body", value: "이야기 ID: \(storyID.uuidString)\n사유: \(reasons.first { $0.0 == reason }?.1 ?? reason)\n\(detail.prefix(1000))")]
        guard let target = url.url else { return }
        openURL(target) { accepted in
            notice = accepted ? "메일 앱에서 내용을 확인하고 직접 전송해 주세요. 아직 신고가 접수된 것은 아닙니다." : "메일 앱을 열지 못했어요. 문의 주소와 이야기 ID를 복사해 이메일로 보내 주세요."
        }
    }
}

struct OiBlockedAuthorsView: View {
    @Environment(\.dismiss) private var dismiss
    private var store: OiContentSafetyStore { .shared }
    var body: some View {
        NavigationStack {
            List {
                Text("이 기기의 본 앱과 App Clip에 적용됩니다. 계정이나 원래 수집 기록은 삭제하지 않습니다.")
                    .font(.footnote)
                if let error = store.error {
                    Text(error)
                    Button("다시 읽기") { store.reload() }
                }
                if store.authors.isEmpty { Text("차단한 작성자가 없어요.") }
                ForEach(store.authors.keys.sorted(), id: \.self) { id in
                    HStack {
                        Text(store.authors[id] ?? "작성자")
                        Spacer()
                        Button("차단 해제") {
                            if let uuid = UUID(uuidString: id) { store.setBlocked(uuid, name: "", blocked: false) }
                        }
                    }
                }
            }.navigationTitle("차단한 작성자")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
                .onAppear { store.reload() }
        }
    }
}
