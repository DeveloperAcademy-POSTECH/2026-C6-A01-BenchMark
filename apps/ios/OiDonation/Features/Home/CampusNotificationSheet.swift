//
//  CampusNotificationSheet.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct CampusNotificationOverlay: View {
    let remote: OiRemoteStore
    let dismiss: () -> Void
    var onOpenContinuation: ((String) -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CampusStoryStore.self) private var storyStore: CampusStoryStore?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var requests: [OiCardRequestInboxItem] = []
    @State private var isLoading = false
    @State private var hasFinishedInitialLoad = false
    @State private var hasLoadedDecision = false
    @State private var requestLoadFailed = false
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
    @State private var retryAttempt = 0
    @State private var timestamp = Date.now
    @State private var hasLoadedContinuationPages = false
    @State private var inboxIsAtTop = true
    @State private var detailIsAtTop = true
    @State private var swipe = Swipe.idle
    @State private var isClosing = false
    @GestureState private var isSwiping = false

    private enum Swipe: Equatable {
        case idle
        case scrolling
        case dismissing(CGFloat)

        var offset: CGFloat {
            guard case let .dismissing(distance) = self else { return 0 }
            return max(0, distance)
        }
    }

    private enum FailedLoad: Equatable {
        case inbox
        case continuationPage
    }

    private var canClose: Bool {
        pendingRequestID == nil && !openingContinuation && !isClosing
    }

    var body: some View {
        GeometryReader { viewport in
            ZStack {
                Color.black.opacity(isClosing ? 0 : 0.2)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)

                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: 35, topTrailingRadius: 35)
                            .fill(CampusStyle.mapSheet.opacity(reduceTransparency || contrast == .increased ? 1 : 0.7))
                            .ignoresSafeArea(edges: [.horizontal, .bottom])
                    }
                    .offset(y: isClosing ? viewport.size.height + viewport.safeAreaInsets.bottom : swipe.offset)
                    .simultaneousGesture(dismissSwipe)
                    .allowsHitTesting(!isClosing)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityIdentifier("campus.notifications.panel")
            }
        }
        .onChange(of: isSwiping) { _, active in
            if !active, !isClosing { resetSwipe() }
        }
        .task(id: remote.continuationPrivacyKey) {
            loadID = UUID(); isLoading = false; continuations = []; continuationCursor = nil
            requests = []; hasFinishedInitialLoad = false; failedLoad = nil
            selectedRequestID = nil; showingOlderRequests = false
            hasLoadedDecision = false; requestLoadFailed = false
            unconfirmedDecision = nil; actionError = nil
            hasLoadedContinuationPages = false
            await reload()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                timestamp = .now
                if hasFinishedInitialLoad, failedLoad == nil, !hasLoadedContinuationPages {
                    await reload()
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: retryAttempt) {
            guard retryAttempt > 0 else { return }
            await retryLoad()
        }
        .alert("이어진 이야기를 열지 못했어요", isPresented: Binding(
            get: { continuationError != nil }, set: { if !$0 { continuationError = nil } })) {
                Button("확인", role: .cancel) { continuationError = nil }
            } message: { Text(continuationError ?? "") }
        .onChange(of: remote.needsReauthentication) { _, needsReauthentication in
            if needsReauthentication {
                selectedRequestID = nil
                showingOlderRequests = false
                requests = []
                continuations = []; continuationCursor = nil; loadID = UUID()
                hasFinishedInitialLoad = false
                failedLoad = nil
                actionError = nil
                unconfirmedDecision = nil
            }
        }
    }

    private var panel: some View {
        let now = timestamp
        let recentRequests = requests.filter { Self.isRecent($0.createdAt, now: now) }
        let hasOlderRequests = recentRequests.count != requests.count
        let hasSession = remote.account != nil && !remote.needsReauthentication
        let showsDetail = hasSession && (selectedRequestID != nil || showingOlderRequests)

        return ZStack {
            CampusNotificationInboxView(
                requests: hasSession ? recentRequests : [],
                isLoading: hasSession && (isLoading || !hasFinishedInitialLoad),
                isInitialLoading: hasSession && !hasFinishedInitialLoad,
                loadFailed: hasSession && failedLoad != nil,
                onRetry: hasSession ? { retryAttempt += 1 } : nil,
                unconfirmedRequestID: hasSession ? unconfirmedDecision?.id : nil,
                onOpenOlderRequests: hasSession && hasOlderRequests ? { showingOlderRequests = true } : nil,
                onOpenRequest: { id in
                    guard hasSession else { return }
                    if unconfirmedDecision == nil { actionError = nil }
                    selectedRequestID = id
                },
                continuations: hasSession ? continuations.filter { Self.isRecent($0.createdAt, now: now) } : [],
                onOpenContinuation: { id in Task { await openContinuation(id) } },
                onMoreContinuations: continuationCursor == nil || failedLoad != nil ? nil : { Task { await loadMoreContinuations() } }
            )
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                inboxIsAtTop = atTop
            }
            .opacity(showsDetail ? 0 : 1)
            .disabled(openingContinuation || showsDetail)
            .accessibilityHidden(showsDetail)
            .accessibilityAction(.escape, close)

            if hasSession, let selectedRequestID {
                requestDetail(requests.filter { $0.id == selectedRequestID }, title: "카드 요청")
            } else if hasSession, showingOlderRequests {
                requestDetail(requests.filter { !Self.isRecent($0.createdAt, now: now) }, title: "이전 카드 요청")
            }
        }
        .onChange(of: showsDetail) { _, _ in detailIsAtTop = true }
        .onChange(of: failedLoad) { _, failure in
            if failure != nil { inboxIsAtTop = true; detailIsAtTop = true }
        }
    }

    private var dismissSwipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($isSwiping) { _, active, _ in active = true }
            .onChanged { gesture in
                guard canClose else { return }
                let distance = gesture.translation.height
                switch swipe {
                case .idle:
                    let showsDetail = selectedRequestID != nil || showingOlderRequests
                    let isAtTop = showsDetail ? detailIsAtTop : inboxIsAtTop
                    swipe = isAtTop && distance > abs(gesture.translation.width) ? .dismissing(distance) : .scrolling
                case .dismissing:
                    swipe = .dismissing(distance)
                case .scrolling:
                    break
                }
            }
            .onEnded { gesture in
                if swipe.offset > 72 || (swipe.offset > 24 && gesture.predictedEndTranslation.height > 144) {
                    close()
                } else {
                    resetSwipe()
                }
            }
    }

    private func close() {
        guard canClose else { return }
        if reduceMotion {
            dismiss()
        } else {
            withAnimation(.easeOut(duration: 0.24), completionCriteria: .logicallyComplete) {
                isClosing = true
            } completion: {
                dismiss()
            }
        }
    }

    private func resetSwipe() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { swipe = .idle }
    }

    static func isRecent(_ createdAt: Date, now: Date) -> Bool {
        createdAt > now.addingTimeInterval(-30 * 24 * 60 * 60)
    }

    private func requestDetail(_ rows: [OiCardRequestInboxItem], title: String) -> some View {
        NavigationStack {
            OiCardRequestInboxView(
                requests: rows,
                isLoading: isLoading,
                loadError: requestLoadFailed ? "카드 요청을 불러오지 못했어요. 다시 시도해 주세요." : nil,
                pendingRequestID: pendingRequestID,
                actionError: actionError,
                onReload: reload,
                onDecision: resolve,
                onRetryDecision: retryAction,
                showsHeader: false,
                decisionsEnabled: hasLoadedDecision
            )
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                detailIsAtTop = atTop
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if pendingRequestID == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: closeRequestDetail) {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("알림 목록으로 돌아가기")
                    }
                }
            }
            .accessibilityAction(.escape) { closeRequestDetail() }
        }
    }

    private func closeRequestDetail() {
        guard pendingRequestID == nil else { return }
        selectedRequestID = nil
        showingOlderRequests = false
    }

    private func reload() async {
        guard !isLoading, pendingRequestID == nil, !remote.needsReauthentication,
              let owner = remote.account?.id else { return }
        isLoading = true
        timestamp = .now
        var loadFailed = false
        let started = loadID
        let privacy = remote.continuationPrivacyKey
        defer { if loadID == started { isLoading = false } }
        func isCurrent() -> Bool {
            !Task.isCancelled && loadID == started && privacy == remote.continuationPrivacyKey
        }
        do {
            let saved = try await remote.pendingCardDecision(owner: owner)
            guard isCurrent() else { return }
            unconfirmedDecision = saved
            hasLoadedDecision = true
            if saved != nil { actionError = "처리 결과를 확인하지 못했어요. 같은 응답을 다시 확인해 주세요." }
        } catch {
            guard isCurrent() else { return }
            hasLoadedDecision = false
            loadFailed = true
        }
        do {
            let rows = try await remote.cardRequests()
            guard isCurrent() else { return }
            requests = rows.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }.map {
                OiCardRequestInboxItem(id: $0.id, requesterName: $0.requesterName,
                    storyTitle: $0.storyTitle, schoolName: $0.requesterSchoolName,
                    portraitURL: nil, createdAt: $0.createdAt)
            }
            requestLoadFailed = !hasLoadedDecision
        } catch {
            guard isCurrent() else { return }
            requestLoadFailed = true
            loadFailed = true
        }
        if remote.supportsContinuationNotifications {
            do {
                let page = try await remote.storyContinuations(mine: true)
                guard isCurrent() else { return }
                continuations = Self.notices(page.items, remote: remote)
                continuationCursor = continuations.count == page.items.count ? page.nextCursor : nil
                hasLoadedContinuationPages = false
            } catch {
                guard isCurrent() else { return }
                loadFailed = true
            }
        }
        guard isCurrent() else { return }
        hasFinishedInitialLoad = true
        failedLoad = loadFailed ? .inbox : nil
    }

    private func retryLoad() async {
        switch failedLoad {
        case .inbox: await reload()
        case .continuationPage: await loadMoreContinuations()
        case nil: break
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
        guard !isLoading, hasLoadedDecision, pendingRequestID == nil, !remote.needsReauthentication,
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
