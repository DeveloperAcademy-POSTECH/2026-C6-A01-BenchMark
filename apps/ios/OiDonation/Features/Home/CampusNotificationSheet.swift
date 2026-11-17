//
//  CampusNotificationSheet.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct CampusNotificationSheet: View {
    let remote: OiRemoteStore
    var onOpenContinuation: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CampusStoryStore.self) private var storyStore: CampusStoryStore?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var requests: [OiCardRequestInboxItem] = []
    @State private var isLoading = false
    @State private var hasLoadedRequests = false
    @State private var selectedRequestID: UUID?
    @State private var showingOlderRequests = false
    @State private var pendingRequestID: UUID?
    @State private var failedLoad: FailedLoad?
    @State private var actionError: String?
    @State private var unconfirmedDecision: OiPendingCardDecision?
    @State private var continuations: [OiContinuationNotice] = []
    @State private var continuationCursor: OiContinuationCursor?
    @State private var openingContinuation = false
    @State private var continuationError: String?
    @State private var loadID = UUID()
    @State private var timestamp = Date.now
    @State private var hasLoadedContinuationPages = false

    private enum FailedLoad: Equatable {
        case inbox
        case continuationPage
    }

    private var retryTarget: FailedLoad? {
        guard scenePhase == .active, remote.account != nil, !remote.needsReauthentication else { return nil }
        return failedLoad
    }

    var body: some View {
        let now = timestamp
        let recentRequests = requests.filter { Self.isRecent($0.createdAt, now: now) }
        let hasOlderRequests = recentRequests.count != requests.count
        let hasSession = remote.account != nil && !remote.needsReauthentication
        NavigationStack {
            CampusNotificationInboxView(
                requests: hasSession ? recentRequests : [],
                isLoading: hasSession && (isLoading || !hasLoadedRequests),
                isInitialLoading: hasSession && !hasLoadedRequests,
                loadFailed: hasSession && failedLoad != nil,
                unconfirmedRequestID: hasSession ? unconfirmedDecision?.id : nil,
                onOpenOlderRequests: hasSession && hasOlderRequests ? { showingOlderRequests = true } : nil,
                onOpenRequest: { id in
                    guard hasSession else { return }
                    if unconfirmedDecision == nil { actionError = nil }
                    selectedRequestID = id
                },
                continuations: hasSession ? continuations.filter { Self.isRecent($0.createdAt, now: now) } : [],
                onOpenContinuation: { id in Task { await openContinuation(id) } },
                onMoreContinuations: continuationCursor == nil ? nil : { Task { await loadMoreContinuations() } }
            )
            .task(id: remote.continuationPrivacyKey) {
                loadID = UUID(); isLoading = false; continuations = []; continuationCursor = nil
                requests = []; hasLoadedRequests = false; failedLoad = nil
                hasLoadedContinuationPages = false
                await reload()
            }
            .disabled(openingContinuation)
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                timestamp = .now
                if hasLoadedRequests, failedLoad == nil, !hasLoadedContinuationPages {
                    await reload()
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: retryTarget) {
            guard let target = retryTarget else { return }
            await retryLoads(target)
        }
        .interactiveDismissDisabled(pendingRequestID != nil || openingContinuation)
        .alert("이어진 이야기를 열지 못했어요", isPresented: Binding(
            get: { continuationError != nil }, set: { if !$0 { continuationError = nil } })) {
                Button("확인", role: .cancel) { continuationError = nil }
            } message: { Text(continuationError ?? "") }
        .presentationDetents([.large])
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.resizes)
        .presentationBackground {
            UnevenRoundedRectangle(topLeadingRadius: 35, topTrailingRadius: 35)
                .fill(CampusStyle.mapSheet.opacity(reduceTransparency || contrast == .increased ? 1 : 0.7))
        }
        .onChange(of: remote.needsReauthentication) { _, needsReauthentication in
            if needsReauthentication {
                selectedRequestID = nil
                showingOlderRequests = false
                requests = []
                continuations = []; continuationCursor = nil; loadID = UUID()
                hasLoadedRequests = false
                failedLoad = nil
                actionError = nil
                unconfirmedDecision = nil
            }
        }
    }

    static func isRecent(_ createdAt: Date, now: Date) -> Bool {
        createdAt > now.addingTimeInterval(-30 * 24 * 60 * 60)
    }

    private func requestDetail(_ rows: [OiCardRequestInboxItem], title: String) -> some View {
        Group {
            if failedLoad != nil {
                ProgressView().accessibilityLabel("알림을 불러오는 중이에요")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OiCardRequestInboxView(
                    requests: rows,
                    isLoading: isLoading,
                    loadError: nil,
                    pendingRequestID: pendingRequestID,
                    actionError: actionError,
                    onReload: reload,
                    onDecision: resolve,
                    onRetryDecision: retryAction,
                    showsHeader: false
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(pendingRequestID != nil)
    }

    private func reload() async {
        guard !isLoading, pendingRequestID == nil, !remote.needsReauthentication,
              let owner = remote.account?.id else { return }
        isLoading = true
        timestamp = .now
        var loadFailed = false
        let started = loadID
        defer { if loadID == started { isLoading = false } }
        do {
            let saved = try await remote.pendingCardDecision(owner: owner)
            guard loadID == started, !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication else { return }
            unconfirmedDecision = saved
            if saved != nil { actionError = "처리 결과를 확인하지 못했어요. 같은 응답을 다시 확인해 주세요." }
            let rows = try await remote.cardRequests()
            guard !Task.isCancelled, loadID == started, remote.account?.id == owner, !remote.needsReauthentication else { return }
            requests = rows.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }.map {
                OiCardRequestInboxItem(id: $0.id, requesterName: $0.requesterName,
                    storyTitle: $0.storyTitle, schoolName: $0.requesterSchoolName,
                    portraitURL: nil, createdAt: $0.createdAt)
            }
        } catch {
            guard !Task.isCancelled, loadID == started, remote.account?.id == owner, !remote.needsReauthentication else { return }
            loadFailed = true
        }
        if remote.supportsContinuationNotifications {
            do {
                let page = try await remote.storyContinuations(mine: true)
                guard loadID == started, remote.account?.id == owner, !Task.isCancelled else { return }
                continuations = Self.notices(page.items, remote: remote)
                continuationCursor = continuations.count == page.items.count ? page.nextCursor : nil
                hasLoadedContinuationPages = false
            } catch {
                guard loadID == started, remote.account?.id == owner, !Task.isCancelled else { return }
                loadFailed = true
            }
        }
        guard loadID == started, remote.account?.id == owner, !remote.needsReauthentication, !Task.isCancelled else { return }
        hasLoadedRequests = !loadFailed
        failedLoad = loadFailed ? .inbox : nil
    }

    private func retryLoads(_ target: FailedLoad) async {
        var delay = 2
        while !Task.isCancelled && retryTarget == target {
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, retryTarget == target else { return }
            switch target {
            case .inbox: await reload()
            case .continuationPage: await loadMoreContinuations()
            }
            delay = min(delay * 2, 15)
        }
    }

    static func notices(_ rows: [OiStoryContinuation], remote: OiRemoteStore, now: Date = .now) -> [OiContinuationNotice] {
        rows.compactMap { row in
            let date = ISO8601DateFormatter()
            date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let created = date.date(from: row.publishedAt) ?? ISO8601DateFormatter().date(from: row.publishedAt)
            guard let created, isRecent(created, now: now) else { return nil }
            let story = remote.campusStory(row.story)
            return OiContinuationNotice(id: row.id, title: story.storyTitle, author: story.donor,
                createdAt: created, isUnread: row.readAt == nil)
        }
    }

    private func loadMoreContinuations() async {
        guard !isLoading, pendingRequestID == nil, let continuationCursor else { return }
        let started = loadID
        isLoading = true
        defer { if loadID == started { isLoading = false } }
        do {
            let page = try await remote.storyContinuations(mine: true, cursor: continuationCursor)
            guard !Task.isCancelled, loadID == started else { return }
            let notices = Self.notices(page.items, remote: remote), known = Set(continuations.map(\.id))
            continuations += notices.filter { !known.contains($0.id) }
            hasLoadedContinuationPages = true
            self.continuationCursor = notices.count == page.items.count ? page.nextCursor : nil
            failedLoad = nil
        } catch {
            if !Task.isCancelled, loadID == started { failedLoad = .continuationPage }
        }
    }

    private func openContinuation(_ child: UUID) async {
        guard !openingContinuation, pendingRequestID == nil, unconfirmedDecision == nil,
              let owner = remote.account?.id, !remote.needsReauthentication else { return }
        openingContinuation = true
        defer { openingContinuation = false }
        do {
            // Revalidate current visibility and ownership before marking read or navigating.
            let story = try await remote.readStoryContinuation(child)
            guard !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication else { return }
            if let storyStore {
                storyStore.synchronize(stories: storyStore.stories.filter { $0.id != story.id } + [story], collected: storyStore.collected)
            }
            onOpenContinuation?(story.id)
        } catch {
            guard !Task.isCancelled, remote.account?.id == owner else { return }
            continuationError = "비공개 또는 삭제된 이야기는 열 수 없어요. 연결 상태를 확인하고 다시 시도해 주세요."
            await reload()
        }
    }

    private func resolve(_ id: UUID, _ decision: OiCardRequestDecision) async {
        guard !isLoading, pendingRequestID == nil, !remote.needsReauthentication,
              let owner = remote.account?.id else { return }
        let submitted = OiPendingCardDecision(id: id, accept: decision == .accept)
        if let unconfirmedDecision {
            guard unconfirmedDecision == submitted else { return }
        } else {
            guard requests.contains(where: { $0.id == id }) else { return }
        }
        unconfirmedDecision = nil
        pendingRequestID = id
        actionError = nil
        do {
            try await remote.resolveRecoverableCardDecision(submitted, owner: owner)
            if remote.account?.id == owner, !remote.needsReauthentication {
                requests.removeAll { $0.id == id }
                selectedRequestID = nil
            }
        } catch {
            if !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication {
                if case OiServiceError.conflict = error {
                    actionError = "이미 처리됐거나 더 이상 응답할 수 없는 요청이에요."
                } else {
                    unconfirmedDecision = submitted
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
        await resolve(unconfirmedDecision.id, unconfirmedDecision.accept ? .accept : .reject)
    }

    private var retryAction: (() async -> Void)? {
        guard unconfirmedDecision != nil else { return nil }
        return { await retryDecision() }
    }
}
