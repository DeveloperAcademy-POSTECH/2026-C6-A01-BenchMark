//
//  CampusCardRequestSheet.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct CampusCardRequestSheet: View {
    let remote: OiRemoteStore

    @Environment(\.dismiss) private var dismiss
    @State private var requests: [OiCardRequestInboxItem] = []
    @State private var isLoading = false
    @State private var pendingRequestID: UUID?
    @State private var loadError: String?
    @State private var actionError: String?

    var body: some View {
        if remote.account == nil || remote.needsReauthentication {
            NavigationStack {
                ContentUnavailableView {
                    Label("카드 요청을 보려면 로그인해 주세요", systemImage: "envelope")
                } actions: {
                    NavigationLink("설정에서 로그인하기") { MYSettingsView(remote: remote) }
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle("받은 카드 요청")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
            }
        } else {
            OiCardRequestInboxView(
                requests: requests,
                isLoading: isLoading,
                loadError: loadError,
                pendingRequestID: pendingRequestID,
                actionError: actionError,
                onReload: reload,
                onDecision: resolve
            )
            .interactiveDismissDisabled(pendingRequestID != nil)
        }
    }

    private func reload() async {
        guard !isLoading, pendingRequestID == nil, let owner = remote.account?.id else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows = try await remote.cardRequests()
            guard !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication else { return }
            requests = rows.filter { $0.status == .pending }.map {
                OiCardRequestInboxItem(id: $0.id, requesterName: $0.requesterName,
                    storyTitle: $0.storyTitle, schoolName: $0.requesterSchoolName,
                    portraitURL: nil, createdAt: $0.createdAt)
            }
        } catch {
            guard !Task.isCancelled, !OiServiceFailure.isCancellation(error), remote.account?.id == owner else { return }
            loadError = "연결 상태를 확인한 뒤 다시 시도해 주세요."
        }
    }

    private func resolve(_ id: UUID, _ decision: OiCardRequestDecision) async {
        guard !isLoading, pendingRequestID == nil, requests.contains(where: { $0.id == id }),
              let owner = remote.account?.id else { return }
        pendingRequestID = id
        actionError = nil
        do {
            try await remote.resolveCardRequest(id, accept: decision == .accept)
            if remote.account?.id == owner { requests.removeAll { $0.id == id } }
        } catch {
            if !Task.isCancelled, !OiServiceFailure.isCancellation(error), remote.account?.id == owner {
                if case OiServiceError.conflict = error {
                    actionError = "이미 처리됐거나 더 이상 응답할 수 없는 요청이에요."
                } else {
                    actionError = "응답을 확인하지 못했어요. 목록을 확인한 뒤 다시 시도해 주세요."
                }
            }
        }
        pendingRequestID = nil
        if !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication {
            await reload()
        }
    }
}
