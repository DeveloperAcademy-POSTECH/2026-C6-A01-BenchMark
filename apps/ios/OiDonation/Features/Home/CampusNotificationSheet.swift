//
//  CampusNotificationSheet.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct CampusNotificationSheet: View {
    let remote: OiRemoteStore

    @Environment(\.dismiss) private var dismiss
    @State private var requests: [OiCardRequestInboxItem] = []
    @State private var isLoading = false
    @State private var hasLoadedRequests = false
    @State private var selectedRequestID: UUID?
    @State private var pendingRequestID: UUID?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var unconfirmedDecision: (id: UUID, decision: OiCardRequestDecision)?

    var body: some View {
        NavigationStack {
            Group {
                if remote.account == nil || remote.needsReauthentication {
                    ContentUnavailableView {
                        Label("알림을 보려면 로그인해 주세요", systemImage: "envelope")
                    } actions: {
                        NavigationLink("설정에서 로그인하기") { MYSettingsView(remote: remote) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    CampusNotificationInboxView(
                        requests: requests,
                        isLoading: isLoading || (!hasLoadedRequests && loadError == nil),
                        loadError: loadError,
                        unconfirmedRequestID: unconfirmedDecision?.id,
                        onReload: reload,
                        onOpenRequest: { id in
                            if unconfirmedDecision == nil { actionError = nil }
                            selectedRequestID = id
                        }
                    )
                    .task { await reload() }
                }
            }
            .navigationTitle("알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark", action: { dismiss() })
                        .labelStyle(.iconOnly)
                        .disabled(pendingRequestID != nil)
                        .accessibilityIdentifier("campus.notifications.close")
                }
            }
            .navigationDestination(item: $selectedRequestID) { id in
                if remote.account != nil && !remote.needsReauthentication {
                    requestDetail(id)
                }
            }
        }
        .interactiveDismissDisabled(pendingRequestID != nil)
        .modifier(CampusCardRequestSheetPresentation())
        .onChange(of: remote.needsReauthentication) { _, needsReauthentication in
            if needsReauthentication {
                selectedRequestID = nil
                requests = []
                hasLoadedRequests = false
                loadError = nil
                actionError = nil
                unconfirmedDecision = nil
            }
        }
    }

    private func requestDetail(_ id: UUID) -> some View {
        OiCardRequestInboxView(
            requests: requests.filter { $0.id == id },
            isLoading: isLoading,
            loadError: loadError,
            pendingRequestID: pendingRequestID,
            actionError: actionError,
            onReload: reload,
            onDecision: resolve,
            onRetryDecision: retryAction,
            showsHeader: false
        )
        .navigationTitle("카드 요청")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(pendingRequestID != nil)
    }

    private func reload() async {
        guard !isLoading, pendingRequestID == nil, !remote.needsReauthentication,
              let owner = remote.account?.id else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows = try await remote.cardRequests()
            guard !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication else { return }
            requests = rows.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }.map {
                OiCardRequestInboxItem(id: $0.id, requesterName: $0.requesterName,
                    storyTitle: $0.storyTitle, schoolName: $0.requesterSchoolName,
                    portraitURL: nil, createdAt: $0.createdAt)
            }
            hasLoadedRequests = true
        } catch {
            guard !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication else { return }
            loadError = "연결 상태를 확인한 뒤 다시 시도해 주세요."
        }
    }

    private func resolve(_ id: UUID, _ decision: OiCardRequestDecision) async {
        guard !isLoading, pendingRequestID == nil, !remote.needsReauthentication,
              let owner = remote.account?.id else { return }
        if let unconfirmedDecision {
            guard unconfirmedDecision.id == id, unconfirmedDecision.decision == decision else { return }
        } else {
            guard requests.contains(where: { $0.id == id }) else { return }
        }
        unconfirmedDecision = nil
        pendingRequestID = id
        actionError = nil
        do {
            try await remote.resolveCardRequest(id, accept: decision == .accept)
            if remote.account?.id == owner, !remote.needsReauthentication {
                requests.removeAll { $0.id == id }
                selectedRequestID = nil
            }
        } catch {
            if !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication {
                if case OiServiceError.conflict = error {
                    actionError = "이미 처리됐거나 더 이상 응답할 수 없는 요청이에요."
                } else {
                    unconfirmedDecision = (id, decision)
                    actionError = "처리 결과를 확인하지 못했어요. 같은 응답을 다시 확인해 주세요."
                }
            }
        }
        pendingRequestID = nil
        if !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication {
            await reload()
        }
    }

    private func retryDecision() async {
        guard let unconfirmedDecision else { return }
        // The server accepts a replay of the same decision, including after the
        // request stops appearing in the pending inbox.
        await resolve(unconfirmedDecision.id, unconfirmedDecision.decision)
    }

    private var retryAction: (() async -> Void)? {
        guard unconfirmedDecision != nil else { return nil }
        return { await retryDecision() }
    }
}

/// Let the system own the glass, corners, and transition to an opaque full-height sheet.
struct CampusCardRequestSheetPresentation: ViewModifier {
    @State private var detent: PresentationDetent = .medium

    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.resizes)
    }
}
