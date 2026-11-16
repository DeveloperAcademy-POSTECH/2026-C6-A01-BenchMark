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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var requests: [OiCardRequestInboxItem] = []
    @State private var isLoading = false
    @State private var hasLoadedRequests = false
    @State private var selectedRequestID: UUID?
    @State private var showingOlderRequests = false
    @State private var pendingRequestID: UUID?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var unconfirmedDecision: (id: UUID, decision: OiCardRequestDecision)?

    var body: some View {
        let now = Date.now
        let recentRequests = requests.filter { Self.isRecent($0.createdAt, now: now) }
        let hasOlderRequests = recentRequests.count != requests.count
        let hasSession = remote.account != nil && !remote.needsReauthentication
        NavigationStack {
            CampusNotificationInboxView(
                requests: hasSession ? recentRequests : [],
                isLoading: hasSession && (isLoading || (!hasLoadedRequests && loadError == nil)),
                loadError: hasSession ? loadError : nil,
                unconfirmedRequestID: hasSession ? unconfirmedDecision?.id : nil,
                onOpenOlderRequests: hasSession && hasOlderRequests ? { showingOlderRequests = true } : nil,
                onReload: reload,
                onOpenRequest: { id in
                    guard hasSession else { return }
                    if unconfirmedDecision == nil { actionError = nil }
                    selectedRequestID = id
                }
            )
            .task { await reload() }
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityAction(.escape) { if pendingRequestID == nil { dismiss() } }
            .navigationDestination(item: $selectedRequestID) { id in
                if remote.account != nil && !remote.needsReauthentication {
                    requestDetail(requests.filter { $0.id == id }, title: "카드 요청")
                }
            }
            .navigationDestination(isPresented: $showingOlderRequests) {
                if remote.account != nil && !remote.needsReauthentication {
                    requestDetail(requests.filter { !Self.isRecent($0.createdAt, now: now) }, title: "이전 카드 요청")
                }
            }
        }
        .interactiveDismissDisabled(pendingRequestID != nil)
        .presentationDetents([.large])
        .presentationCornerRadius(35)
        .presentationDragIndicator(.hidden)
        .presentationBackground {
            CampusStyle.mapSheet.opacity(reduceTransparency || contrast == .increased ? 1 : 0.7)
        }
        .onChange(of: remote.needsReauthentication) { _, needsReauthentication in
            if needsReauthentication {
                selectedRequestID = nil
                showingOlderRequests = false
                requests = []
                hasLoadedRequests = false
                loadError = nil
                actionError = nil
                unconfirmedDecision = nil
            }
        }
    }

    static func isRecent(_ createdAt: Date, now: Date) -> Bool {
        createdAt > now.addingTimeInterval(-30 * 24 * 60 * 60)
    }

    private func requestDetail(_ rows: [OiCardRequestInboxItem], title: String) -> some View {
        OiCardRequestInboxView(
            requests: rows,
            isLoading: isLoading,
            loadError: loadError,
            pendingRequestID: pendingRequestID,
            actionError: actionError,
            onReload: reload,
            onDecision: resolve,
            onRetryDecision: retryAction,
            showsHeader: false
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
