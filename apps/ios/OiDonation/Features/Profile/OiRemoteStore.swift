//
//  OiRemoteStore.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import Foundation
import Observation
import UIKit

@MainActor @Observable
final class OiRemoteStore: OiOperatorStoryServing, OiOperatorEvidenceServing, OiOperatorEvidenceHistoryServing, OiOperatorEvidenceAnalysisServing, OiOperatorAuditServing {
    // Avoid the synthesized isolated deinit crash on early iOS 26 (Swift #88036).
    nonisolated deinit {}

    private(set) var schools: [OiSchool] = []
    private(set) var regions: [OiRegion] = []
    private(set) var assets: [OiAsset] = []
    private(set) var account: OiAccount?
    private(set) var profile: OiProfile?
    private var loadedStories: [OiLiveStory] = []
    var stories: [OiLiveStory] { loadedStories.filter { !OiContentSafetyStore.shared.isBlocked($0.userId) } }
    private(set) var ownStories: [OiLiveStory] = []
    private(set) var reviewStories: [OiLiveStory] = []
    private(set) var profiles: [OiProfile] = []
    private(set) var media: [OiMedia] = []
    private(set) var evidence: [OiEvidence] = []
    private(set) var unapprovedDraftsEnabled = false
    private(set) var canPublishCucumberAppearance = false
    private(set) var canPublishStoryCard = false

    var canPlaceOi: Bool { account != nil && !needsReauthentication && !isAccountDeletionPending }

    var canStartStory: Bool {
        account != nil && !needsReauthentication && hasLoadedRemote && unapprovedDraftsEnabled
    }
    private(set) var collections: [OiOwnedStory] = []
    private(set) var favorites: Set<UUID> = []
    private(set) var collectionCounts: [UUID: Int] = [:]
    private(set) var evidenceOperation: OiEvidenceOperation?
    private(set) var isOperator = false
    private(set) var isBusy = false
    private(set) var isRefreshing = false
    private(set) var hasLoadedRemote = false
    private(set) var needsReauthentication = false
    private(set) var loadError: String?
    private(set) var syncWarning: String?
    private(set) var revision = 0
    private(set) var localPlacementRevision = 0
    private(set) var isConfigured = false
    private(set) var isAccountMergeAvailable = false
    private(set) var isSchoolProfileAvailable = false
    private(set) var isFarmerOutfitAvailable = false
    private(set) var farmerOutfit: OiFarmerOutfit?
    private(set) var accountMemberIDs: Set<UUID> = []
    private(set) var isAccountDeletionPending = false
    private let deletionCleanupKey = "oi.accountDeletion.cleanup.v1"
    private(set) var accountProviders: [String] = []
    private(set) var localRecoveryWarning: String?
    var error: String? { didSet { errorRevision &+= 1 } }
    private var errorRevision = 0
    private var api: OiServiceAPI?
    private var session: OiSession?
    private var refreshTask: Task<OiSession, Error>?
    private var generation = UUID()
    private var loadSequence = 0
    private var localSignOutWarning: String?
    private var committedMediaPaths: [UUID:[String]] = [:]
    private let authentication: any OiAuthenticating
    private let drafts: OiDraftVault
    private let vault: any OiSessionStorage

    init(api: OiServiceAPI? = nil, drafts: OiDraftVault = OiDraftVault(), vault: (any OiSessionStorage)? = nil,
         authentication: (any OiAuthenticating)? = nil) {
        self.api = api; self.drafts = drafts; self.vault = vault ?? OiSessionVault()
        self.authentication = authentication ?? OiGoogleAuthentication()
    }

    func start() async {
        var started = generation
        do {
            if api == nil { api = try OiServiceAPI.configured() }
            isConfigured = true
            if let cleanup = UserDefaults.standard.data(forKey: deletionCleanupKey) {
                let receipt = try JSONDecoder().decode(OiAccountDeletionReceipt.self, from: cleanup)
                try await clearDeletedAccount(receipt)
            }
            let restored = try vault.read()
            if (restored?.appAccount ?? restored?.user)?.id != account?.id { resetAccountState() }
            started = generation
            session = restored; account = restored?.appAccount ?? restored?.user
            await refresh()
        } catch {
            guard started == generation, !Task.isCancelled, !OiServiceFailure.isCancellation(error) else { return }
            loadError = error.localizedDescription; self.error = error.localizedDescription
        }
    }

    private func token() async throws -> String {
        guard let api, let current = session else { throw OiServiceError.signInRequired }
        if !current.needsRefresh { return current.accessToken }
        let started = generation
        let refresh: Task<OiSession, Error>
        if let refreshTask { refresh = refreshTask }
        else {
            refresh = Task { try await api.session(grant: "refresh_token", payload: ["refresh_token": current.refreshToken]) }
            refreshTask = refresh
        }
        do {
            var updated = try await refresh.value
            guard started == generation, updated.user.id == current.user.id else { throw OiServiceError.accountChanged }
            updated.appAccount = current.appAccount
            try vault.write(updated); session = updated; refreshTask = nil
            return updated.accessToken
        } catch { if started == generation { refreshTask = nil }; throw error }
    }

    func signIn(using provider: (any OiAuthenticating)? = nil) async {
        guard !isBusy else { return }
        guard let api else { error = OiServiceError.configuration.localizedDescription; return }
        var operationGeneration = generation
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let updated = try await (provider ?? authentication).signIn(api: api)
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            try vault.write(updated); resetAccountState(); session = updated; account = updated.user
            operationGeneration = generation
            do { try await load() }
            catch {
                guard operationGeneration == generation, !Task.isCancelled, !OiServiceFailure.isCancellation(error) else { return }
                loadError = error.localizedDescription; noteAuthenticationFailure(error)
            }
        } catch {
            guard operationGeneration == generation, !Task.isCancelled, !OiServiceFailure.isCancellation(error) else { return }
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let oldToken = session?.accessToken
        do { try vault.write(nil) }
        catch { self.error = "로그아웃 정보를 지우지 못했습니다. 다시 시도해 주세요."; return }
        resetAccountState(); session = nil; account = nil
        do {
            if let oldToken, let api { try await api.signOutCurrentSession(token: oldToken) }
        } catch {
            localSignOutWarning = "이 기기는 로그아웃했지만 서버 세션 정리는 확인하지 못했습니다."
            syncWarning = localSignOutWarning
        }
        do { try await load() }
        catch where OiServiceFailure.isCancellation(error) { }
        catch { loadError = error.localizedDescription }
    }

    func deleteAccount(using provider: any OiAuthenticating) async throws -> OiAccountDeletionReceipt {
        guard let api, let account, !needsReauthentication, !isBusy, !isRefreshing else { throw OiServiceError.signInRequired }
        let started = generation
        isBusy = true
        defer { isBusy = false }
        let proof = try await provider.signIn(api: api)
        try Task.checkCancellation()
        guard started == generation else { throw OiServiceError.accountChanged }
        let accessToken = try await token()
        let receipt: OiAccountDeletionReceipt
        do {
            receipt = try await api.deleteAccount(account.id, token: accessToken, proof: proof)
        } catch {
            guard started == generation else { throw OiServiceError.accountChanged }
            if let status = try? await api.accountDeletionStatus(token: accessToken), status.accountId == account.id {
                showPendingDeletion(status)
            }
            throw error
        }
        guard started == generation else { throw OiServiceError.accountChanged }
        UserDefaults.standard.set(try JSONEncoder().encode(receipt), forKey: deletionCleanupKey)
        resetAccountState(); session = nil; self.account = nil
        do { try await clearDeletedAccount(receipt) }
        catch { syncWarning = "서버 탈퇴는 완료됐지만 기기 기록 정리가 남았어요. 앱을 다시 열면 정리를 재시도해요." }
        if syncWarning == nil {
            do { try await load() }
            catch { loadError = error.localizedDescription }
        }
        return receipt
    }

    private func clearDeletedAccount(_ receipt: OiAccountDeletionReceipt) async throws {
        try vault.write(nil)
        try await drafts.purgeAccounts(Set(receipt.deletedMemberIds))
        for owner in receipt.deletedMemberIds {
            UserDefaults.standard.removeObject(forKey: MYFarmerAppearanceStore.key(ownerID: owner))
        }
        UserDefaults.standard.removeObject(forKey: deletionCleanupKey)
    }

    private func showPendingDeletion(_ status: OiAccountDeletionStatus) {
        guard let id = status.accountId else { return }
        let current = session
        resetAccountState()
        session = current
        account = OiAccount(id: id, email: current?.user.email)
        if var current {
            current.appAccount = account
            session = current
            do { try vault.write(current) }
            catch { localRecoveryWarning = "기기에 탈퇴 진행 상태를 저장하지 못했습니다. 다시 로그인해 삭제를 이어갈 수 있어요." }
        }
        accountMemberIDs = Set(status.memberIds ?? [id])
        isAccountDeletionPending = true
    }

    func authenticateAdditional(using provider: any OiAuthenticating) async throws -> OiSession {
        guard let api, account != nil else { throw OiServiceError.signInRequired }
        guard !isBusy else { throw OiServiceError.unavailable }
        let started = generation
        isBusy = true
        defer { isBusy = false }
        let proof = try await provider.signIn(api: api)
        try Task.checkCancellation()
        guard started == generation else { throw OiServiceError.accountChanged }
        return proof
    }

    func validateCurrentIdentity(_ proof: OiSession) async throws {
        guard try await additionalAccountMatchesCurrent(proof) else {
            throw OiServiceError.server("현재 로그인된 계정을 다시 인증해 주세요. 다른 계정의 인증은 통합 대상 확인 단계에서 진행합니다.")
        }
    }

    func additionalAccountMatchesCurrent(_ proof: OiSession) async throws -> Bool {
        guard let api, let account, !proof.needsRefresh else { throw OiServiceError.signInRequired }
        let started = generation
        let context = try await api.capabilities(token: proof.accessToken)
        try Task.checkCancellation()
        guard started == generation else { throw OiServiceError.accountChanged }
        let matches = (context.accountId ?? proof.user.id) == account.id
        if matches { accountProviders = context.accountProviders ?? accountProviders }
        return matches
    }

    func previewMerge(target: OiSession, source: OiSession, operationID: UUID) async throws -> OiMergePreview {
        guard let api, let account else { throw OiServiceError.signInRequired }
        guard !isBusy, isAccountMergeAvailable, !isOperator else { throw OiServiceError.unavailable }
        guard source.user.id != target.user.id else { throw OiServiceError.server("이미 같은 로그인 계정입니다. 다른 계정으로 인증해 주세요.") }
        let started = generation
        isBusy = true
        defer { isBusy = false }
        let preview = try await api.previewMerge(target: target, source: source, operationID: operationID)
        try Task.checkCancellation()
        guard started == generation, [preview.targetAccountId, preview.sourceAccountId].contains(account.id) else {
            throw OiServiceError.accountChanged
        }
        return preview
    }

    func confirmMerge(target: OiSession, source: OiSession, preview: OiMergePreview, operationID: UUID) async throws -> OiMergeReceipt {
        guard let api, account != nil else { throw OiServiceError.signInRequired }
        guard !isBusy, isAccountMergeAvailable, !isOperator else { throw OiServiceError.unavailable }
        let started = generation
        isBusy = true
        defer { isBusy = false }
        let receipt = try await api.confirmMerge(target: target, source: source, preview: preview, operationID: operationID)
        guard receipt.accountId == preview.targetAccountId, started == generation else { throw OiServiceError.accountChanged }
        // A successful server receipt remains a commit even if the requesting UI was canceled.
        var installed = target
        installed.appAccount = OiAccount(id: receipt.accountId, email: target.user.email)
        do { try vault.write(installed) }
        catch {
            needsReauthentication = true
            throw OiServiceError.server("서버 계정 통합은 완료됐지만 기기 세션 보관에 실패했습니다. 대표 계정으로 다시 로그인해 주세요.")
        }
        resetAccountState(); session = installed; account = installed.appAccount
        await refreshAfterCommit()
        if loadError == nil { syncWarning = "계정 통합이 완료됐습니다. 두 로그인 방법으로 같은 대표 계정을 사용할 수 있습니다." }
        return receipt
    }

    private func resetAccountState() {
        generation = UUID(); loadSequence += 1; refreshTask?.cancel(); refreshTask = nil
        profile = nil; ownStories = []; reviewStories = []; profiles = []; media = []; evidence = []
        loadedStories = []; collections = []; favorites = []; collectionCounts = [:]; evidenceOperation = nil; committedMediaPaths = [:]
        unapprovedDraftsEnabled = false
        isAccountDeletionPending = false; isOperator = false; hasLoadedRemote = false; needsReauthentication = false; isRefreshing = false
        isAccountMergeAvailable = false; accountMemberIDs = []; accountProviders = []; localRecoveryWarning = nil
        isSchoolProfileAvailable = false; isFarmerOutfitAvailable = false; farmerOutfit = nil
        canPublishCucumberAppearance = false
        canPublishStoryCard = false
        localSignOutWarning = nil; loadError = nil; syncWarning = nil; error = nil; revision += 1
    }

    private func noteAuthenticationFailure(_ error: Error) {
        if case OiServiceError.signInRequired = error, account != nil { needsReauthentication = true }
    }

    /// Fresh server-side capability check, independent of a cached profile/list refresh.
    func verifyOperatorAccess() async throws -> Bool {
        guard let api else { throw OiServiceError.configuration }
        guard account != nil, !needsReauthentication else { throw OiServiceError.signInRequired }
        let started = generation
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            let capabilities = try await api.capabilities(token: accessToken)
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            isOperator = capabilities.operator
            if !isOperator { reviewStories = [] }
            return isOperator
        } catch {
            if started == generation { noteAuthenticationFailure(error) }
            throw error
        }
    }

    private func withOperatorSession<Value>(
        _ operation: (OiServiceAPI, String) async throws -> Value
    ) async throws -> Value {
        let started = generation
        guard try await verifyOperatorAccess() else { throw OiOperatorStoryError.accessDenied }
        guard let api else { throw OiServiceError.configuration }
        let accessToken = try await token()
        guard started == generation else { throw OiServiceError.accountChanged }
        do {
            let result = try await operation(api, accessToken)
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            return result
        } catch {
            if started == generation { noteAuthenticationFailure(error) }
            throw error
        }
    }

    func operatorStories() async throws -> [OiLiveStory] {
        try await withOperatorSession { api, token in
            try await api.rows("oi_stories", query: "status=in.(pending,published,hidden)&order=created_at.desc,id.desc",
                               token: token, as: OiLiveStory.self)
        }
    }

    func operatorEvidenceList() async throws -> [OiEvidence] {
        try await withOperatorSession { api, token in
            try await api.rows("oi_evidence_requests", query: "status=in.(pending,approved,changes_requested,rejected,revoked)&order=submitted_at.desc.nullslast,id.desc",
                               token: token, as: OiEvidence.self).filter { $0.status != "draft" }
        }
    }

    func operatorEvidence(_ id: UUID) async throws -> OiOperatorEvidenceDetail {
        try await withOperatorSession { api, token in
            let rows = try await api.rows("oi_evidence_requests", query: "id=eq.\(id.uuidString)", token: token, as: OiEvidence.self)
            guard rows.count == 1, let row = rows.first, row.id == id, row.status != "draft" else { throw OiEvidenceReviewError.missing }
            let grants = try await api.rows("oi_writing_grants", query: "evidence_id=eq.\(id.uuidString)", token: token, as: OiWritingGrant.self)
            return OiOperatorEvidenceDetail(evidence: row, grants: grants)
        }
    }

    func operatorEvidenceDocument(_ snapshot: OiEvidence) async throws -> OiEvidenceDocument {
        let started = generation
        let latest = try await operatorEvidence(snapshot.id)
        guard latest.evidence == snapshot, let path = snapshot.objectPath else { throw OiServiceError.conflict }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, UUID(uuidString: String(parts[0])) == (snapshot.storageOwnerId ?? snapshot.userId),
              UUID(uuidString: String(parts[1])) == snapshot.id,
              !parts[2].isEmpty, ![".", ".."].contains(String(parts[2])),
              !path.contains("%"), !path.contains("?"), !path.contains("#"), !path.contains("\\") else { throw OiEvidenceReviewError.invalidDocument }
        let document = try await withOperatorSession { api, token in try await api.evidenceDocument(path: path, token: token) }
        guard try await operatorEvidence(snapshot.id).evidence == snapshot else { throw OiServiceError.conflict }
        guard generation == started else { throw OiServiceError.accountChanged }
        return document
    }

    func reviewOperatorEvidence(_ review: OiEvidenceReview) async throws -> OiEvidenceReviewResult {
        guard !isBusy else { throw OiOperatorStoryError.busy }
        let started = generation
        isBusy = true
        defer { isBusy = false }
        do {
            let receipt = try await withOperatorSession { api, token in
                try await api.reviewEvidence(review, token: token)
            }
            guard started == generation else { throw OiServiceError.accountChanged }
            guard receipt.id == review.snapshot.id, receipt.status == review.decision.rawValue,
                  receipt.objectPath == review.snapshot.objectPath, receipt.userId == review.snapshot.userId,
                  receipt.reviewedAt != nil else { throw OiOperatorStoryError.unconfirmedResult }
            applyReceipt(receipt, action: "review_evidence", payload: [:])
            await refreshAfterCommit()
            guard started == generation else { throw OiServiceError.accountChanged }
            return OiEvidenceReviewResult(evidence: receipt, warning: syncWarning)
        } catch {
            if started == generation { noteAuthenticationFailure(error) }
            throw error
        }
    }

    func operatorEvidenceHistory(_ id: UUID) async throws -> [OiEvidenceHistory] {
        try await withOperatorSession { api, token in
            try await api.rows("oi_evidence_history", query: "request_id=eq.\(id.uuidString)&order=recorded_at.desc,id.desc",
                               token: token, as: OiEvidenceHistory.self).filter { $0.requestId == id }
        }
    }

    func operatorAudit(_ query: OiAuditQuery, after cursor: OiAuditCursor?) async throws -> OiAuditPage {
        try await withOperatorSession { api, token in try await api.operatorAudit(query, after: cursor, token: token) }
    }

    func validateOperatorEvidence(_ snapshot: OiEvidence) async throws {
        guard try await operatorEvidence(snapshot.id).evidence == snapshot else { throw OiServiceError.conflict }
    }

    func operatorEvidenceAnalysis(_ snapshot: OiEvidence) async throws -> OiEvidenceAnalysis {
        let started = generation
        guard snapshot.status == "pending" else { throw OiServiceError.conflict }
        try await validateOperatorEvidence(snapshot)
        let result = try await withOperatorSession { api, token in try await api.analyzeEvidence(snapshot, token: token) }
        try await validateOperatorEvidence(snapshot)
        guard generation == started else { throw OiServiceError.accountChanged }
        return result
    }

    func operatorEvidenceHistoryDocument(_ snapshot: OiEvidenceHistory) async throws -> OiEvidenceDocument {
        try await withOperatorSession { api, token in
            func currentHistory() async throws -> OiEvidenceHistory {
                let rows = try await api.rows("oi_evidence_history", query: "id=eq.\(snapshot.id.uuidString)&request_id=eq.\(snapshot.requestId.uuidString)",
                                              token: token, as: OiEvidenceHistory.self)
                guard rows.count == 1, let row = rows.first, row == snapshot else { throw OiServiceError.conflict }
                return row
            }
            _ = try await currentHistory()
            let requests = try await api.rows("oi_evidence_requests", query: "id=eq.\(snapshot.requestId.uuidString)", token: token, as: OiEvidence.self)
            guard requests.count == 1, let request = requests.first, request.id == snapshot.requestId else { throw OiEvidenceReviewError.missing }
            let parts = snapshot.objectPath.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 3, UUID(uuidString: String(parts[0])) == (request.storageOwnerId ?? request.userId),
                  UUID(uuidString: String(parts[1])) == request.id, !parts[2].isEmpty,
                  ![".", ".."].contains(String(parts[2])),
                  !snapshot.objectPath.contains(where: { "%?#\\".contains($0) || $0.asciiValue.map { $0 < 32 } == true })
            else { throw OiEvidenceReviewError.invalidDocument }
            let document = try await api.evidenceDocument(path: snapshot.objectPath, token: token)
            _ = try await currentHistory()
            guard try await api.capabilities(token: token).operator else { throw OiOperatorStoryError.accessDenied }
            return document
        }
    }

    func operatorStory(_ id: UUID) async throws -> OiOperatorStoryDetail {
        try await withOperatorSession { api, token in
            let stories = try await api.rows("oi_stories", query: "id=eq.\(id.uuidString)&status=in.(pending,published,hidden)",
                                            token: token, as: OiLiveStory.self)
            guard stories.count == 1, let story = stories.first, story.id == id else { throw OiOperatorStoryError.storyUnavailable }
            let media = try await api.rows("oi_story_media", query: "story_id=eq.\(id.uuidString)&order=position.asc,id.asc",
                                          token: token, as: OiMedia.self)
            return OiOperatorStoryDetail(story: story, media: media)
        }
    }

    func reviewOperatorStory(_ story: OiLiveStory, publish: Bool) async throws -> OiOperatorStoryReviewResult {
        guard !isBusy else { throw OiOperatorStoryError.busy }
        guard ["pending", "published", "hidden"].contains(story.status),
              story.status != (publish ? "published" : "hidden") else { throw OiServiceError.invalidInput }
        let started = generation
        isBusy = true
        defer { isBusy = false }
        do {
            guard try await verifyOperatorAccess() else { throw OiOperatorStoryError.accessDenied }
            guard let api else { throw OiServiceError.configuration }
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            let wanted = publish ? "published" : "hidden"
            var payload: [String: Any] = ["id": story.id.uuidString, "revision": story.revision, "status": wanted]
            if publish, let appearance = story.cucumberAppearance { payload["appearance_id"] = appearance.id.uuidString.lowercased() }
            if publish, let snapshot = story.cardSnapshotId { payload["card_snapshot_id"] = snapshot.uuidString.lowercased() }
            let receipt = try await api.mutate("review_story", payload: payload, token: accessToken, as: OiLiveStory.self)
            guard started == generation else { throw OiServiceError.accountChanged }
            guard receipt.id == story.id, receipt.status == wanted, receipt.revision > story.revision,
                  receipt.cardSnapshotId == story.cardSnapshotId else {
                throw OiOperatorStoryError.unconfirmedResult
            }
            applyReceipt(receipt, action: "review_story", payload: [:])
            await refreshAfterCommit()
            guard started == generation else { throw OiServiceError.accountChanged }
            return OiOperatorStoryReviewResult(story: receipt, warning: syncWarning)
        } catch {
            if started == generation { noteAuthenticationFailure(error) }
            throw error
        }
    }

    func reportContent(story: UUID, reason: String, detail: String) async throws -> String {
        try await withCardRequestSession { api, token in
            try await api.reportContent(story: story, reason: reason, detail: detail, token: token).status
        }
    }
    func contentReports(offset: Int) async throws -> [OiContentReport] {
        try await withCardRequestSession { api, token in try await api.contentReports(offset: offset, token: token) }
    }
    func reviewContent(report: UUID, action: String, note: String) async throws {
        try await withCardRequestSession { api, token in try await api.reviewContent(report: report, action: action, note: note, token: token) }
        await refresh()
    }

    func cardRequests() async throws -> [OiCardRequest] {
        try await withCardRequestSession { api, token in try await api.cardRequests(token: token) }
    }

    func sendCardRequest(storyID: UUID, requestID: UUID) async throws -> OiCardRequest.Status {
        try await withCardRequestSession { api, token in
            try await api.sendCardRequest(storyID: storyID, requestID: requestID, token: token)
        }
    }

    func resolveCardRequest(_ id: UUID, accept: Bool) async throws {
        _ = try await withCardRequestSession { api, token in
            try await api.resolveCardRequest(id, accept: accept, token: token)
        }
    }

    private func withCardRequestSession<Value>(
        _ operation: (OiServiceAPI, String) async throws -> Value
    ) async throws -> Value {
        guard let api else { throw OiServiceError.configuration }
        guard account != nil, !needsReauthentication else { throw OiServiceError.signInRequired }
        let started = generation
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            let result = try await operation(api, accessToken)
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            return result
        } catch {
            guard started == generation else { throw OiServiceError.accountChanged }
            noteAuthenticationFailure(error)
            throw error
        }
    }

    func refresh() async {
        guard !isBusy, !isRefreshing else { return }
        let started = generation
        let previousErrorRevision = errorRevision
        isRefreshing = true
        defer { if started == generation { isRefreshing = false } }
        do {
            try await load()
            if started == generation, errorRevision == previousErrorRevision { error = nil }
        } catch {
            guard started == generation, !Task.isCancelled, !OiServiceFailure.isCancellation(error) else { return }
            loadError = error.localizedDescription; noteAuthenticationFailure(error)
        }
    }

    /// Always query as the public role so even an owner cannot render a hidden story in AR.
    func publishedStory(_ id: UUID) async throws -> OiLiveStory {
        guard let api else { throw OiServiceError.configuration }
        let story = try await api.publishedStory(id)
        guard !OiContentSafetyStore.shared.isBlocked(story.userId) else { throw OiServiceError.unavailable }
        return story
    }

    func publishedStories() async throws -> [OiLiveStory] {
        guard let api else { throw OiServiceError.configuration }
        return try await api.publishedStories().filter { !OiContentSafetyStore.shared.isBlocked($0.userId) }
    }

    func campusStory(_ item: OiLiveStory, order: Int = 0) -> CampusStory {
        var story = CampusStory(id: item.id.uuidString, regionID: item.regionId, title: item.cucumberName,
            image: item.cucumberAsset, tags: [item.theme, item.emotion],
            donor: profiles.first { $0.id == item.userId }?.nickname ?? "작성자 정보 확인 중",
            location: regions.first { $0.id == item.regionId }?.name ?? "POSTECH",
            date: item.createdDateLabel, order: order, popularity: collectionCounts[item.id] ?? 0, palette: 0)
        story.authorID = item.userId
        story.remoteBody = item.body
        story.remoteMediaPaths = mediaPaths(storyID: item.id)
        story.cucumberPortraitPath = item.cucumberArtwork?.path(.portrait)
        story.cardArtworkPath = item.cardArtworkPath
        story.latitude = item.latitude; story.longitude = item.longitude
        return story
    }

    private func load() async throws {
        guard let api else { throw OiServiceError.configuration }
        let started = generation
        loadSequence += 1
        let sequence = loadSequence
        let accessToken = account == nil ? nil : try await token()
        let capabilities: OiCapabilities?
        if let accessToken {
            do { capabilities = try await api.capabilities(token: accessToken) }
            catch OiServiceError.conflict {
                let status = try await api.accountDeletionStatus(token: accessToken)
                guard started == generation, sequence == loadSequence, status.accountId != nil else { throw OiServiceError.conflict }
                showPendingDeletion(status)
                return
            }
        }
        else { capabilities = nil }
        let resolvedOwner = capabilities?.accountId ?? account?.id
        let members = Set(capabilities?.accountMemberIds ?? resolvedOwner.map { [$0] } ?? [])
        let fetchedSchools = try await api.rows("oi_schools", query: "order=id.asc", as: OiSchool.self)
        let fetchedRegions = try await api.rows("oi_regions", query: "order=id.asc", as: OiRegion.self)
        let fetchedAssets = try await api.rows("oi_assets", query: "order=id.asc", as: OiAsset.self)
        let fetched = try await api.rows("oi_stories", query: "order=created_at.desc,id.asc", token: accessToken, as: OiLiveStory.self)
        let fetchedProfiles = try await api.rows("oi_profiles", token: accessToken, as: OiProfile.self)
        var ownProfile = fetchedProfiles.first { $0.id == resolvedOwner }
        if capabilities?.schoolProfileEnabled == true, let resolvedOwner, let accessToken {
            ownProfile = try await api.schoolProfile(owner: resolvedOwner, token: accessToken)
        }
        var fetchedFarmerOutfit: OiFarmerOutfit?
        if capabilities?.farmerOutfitEnabled == true, let resolvedOwner, let accessToken {
            fetchedFarmerOutfit = try await api.farmerOutfit(owner: resolvedOwner, token: accessToken)
        }
        let fetchedMedia = try await api.rows("oi_story_media", query: "order=position.asc,id.asc", token: accessToken, as: OiMedia.self)
        let metrics = try await api.collectionMetrics(token: accessToken)
        var requests: [OiEvidence] = []
        var collected: [OiOwnedStory] = []; var starred: [OiOwnedStory] = []
        if let accessToken {
            requests = try await api.rows("oi_evidence_requests", query: "order=created_at.desc", token: accessToken, as: OiEvidence.self)
            collected = try await api.rows("oi_collections", query: "order=created_at.desc,story_id.asc", token: accessToken, as: OiOwnedStory.self)
            starred = try await api.rows("oi_favorites", token: accessToken, as: OiOwnedStory.self)
        }
        var recoveredOperation = evidenceOperation
        var recoveryWarning: String?
        if let resolvedOwner {
            if recoveredOperation == nil || account?.id != resolvedOwner {
                do { recoveredOperation = try await drafts.evidence(owner: resolvedOwner) }
                catch { recoveryWarning = "기기의 증빙 재시도 기록을 읽지 못했습니다. 원본은 보관돼 있으며 서버의 제출 상태를 먼저 확인해 주세요." }
            }
            if members != accountMemberIDs || localRecoveryWarning != nil {
                do {
                    if try await drafts.adoptDrafts(from: members, into: resolvedOwner) > 0 {
                        recoveryWarning = "일부 기기 초안·증빙 재시도 기록을 대표 계정으로 복사하지 못했습니다. 원본은 이전 계정 폴더에 보관돼 있습니다."
                    }
                } catch { recoveryWarning = "기기 초안·증빙 기록 통합을 완료하지 못했습니다. 원본은 이전 계정 폴더에 보관돼 있습니다." }
            }
            if recoveredOperation == nil || account?.id != resolvedOwner {
                do { recoveredOperation = try await drafts.evidence(owner: resolvedOwner) }
                catch { recoveryWarning = "기기 증빙 기록을 읽지 못했습니다. 원본은 보관돼 있으며 서버의 제출 상태를 확인해 주세요." }
            }
        }
        try Task.checkCancellation()
        guard started == generation, sequence == loadSequence else { throw CancellationError() }
        if let resolvedOwner, var current = session, account?.id != resolvedOwner {
            let resolved = OiAccount(id: resolvedOwner, email: current.user.email)
            current.appAccount = resolved
            try vault.write(current)
            resetAccountState(); session = current; account = resolved
        }
        schools = fetchedSchools; regions = fetchedRegions; assets = fetchedAssets
        loadedStories = fetched.filter { $0.status == "published" }
        ownStories = fetched.filter { $0.userId == account?.id && $0.status != "deleted" }
        reviewStories = capabilities?.operator == true ? fetched.filter { ["pending","published","hidden"].contains($0.status) } : []
        profile = ownProfile
        profiles = fetchedProfiles; media = fetchedMedia; evidence = requests; committedMediaPaths = [:]
        collections = collected; favorites = Set(starred.map(\.storyId)); isOperator = capabilities?.operator == true
        unapprovedDraftsEnabled = capabilities?.independentStoryCreation == true && capabilities?.unapprovedDraftsEnabled == true
        canPublishCucumberAppearance = capabilities?.publicCucumberAppearance == true
        canPublishStoryCard = capabilities?.publicStoryCard == true
        isAccountMergeAvailable = capabilities?.accountMergeEnabled == true; accountMemberIDs = members
        isSchoolProfileAvailable = capabilities?.schoolProfileEnabled == true
        isFarmerOutfitAvailable = capabilities?.farmerOutfitEnabled == true; farmerOutfit = fetchedFarmerOutfit
        accountProviders = capabilities?.accountProviders ?? []
        evidenceOperation = recoveredOperation; localRecoveryWarning = recoveryWarning
        collectionCounts = metrics.reduce(into: [:]) { $0[$1.storyId] = $1.collectionCount }
        hasLoadedRemote = true; needsReauthentication = false; loadError = nil; syncWarning = localSignOutWarning; revision += 1
    }

    private func refreshAfterCommit() async {
        let started = generation
        do { try await load() }
        catch {
            guard started == generation else { return }
            if Task.isCancelled || OiServiceFailure.isCancellation(error) {
                syncWarning = "서버 저장은 완료됐습니다. 최신 상태 확인은 취소됐으니 다음에 새로고침해 주세요."
                return
            }
            noteAuthenticationFailure(error); loadError = error.localizedDescription
            syncWarning = "서버 저장은 완료됐습니다. 목록 동기화만 실패했으니 중복 제출하지 말고 새로고침해 주세요."
        }
    }

    private struct OiMutationID: Decodable { let id: UUID }

    private func applyReceipt<Value>(_ value: Value, action: String, payload: [String: Any]) {
        loadSequence += 1
        if let story = value as? OiLiveStory {
            ownStories.removeAll { $0.id == story.id }; loadedStories.removeAll { $0.id == story.id }; reviewStories.removeAll { $0.id == story.id }
            if story.userId == account?.id && story.status != "deleted" { ownStories.insert(story, at: 0) }
            if story.status == "published" { loadedStories.insert(story, at: 0) }
            if isOperator && ["pending","published","hidden"].contains(story.status) { reviewStories.insert(story, at: 0) }
        }
        if let request = value as? OiEvidence { evidence.removeAll { $0.id == request.id }; evidence.insert(request, at: 0) }
        if let receipt = value as? OiMutationID {
            if action == "collect", !collections.contains(where: { $0.storyId == receipt.id }) {
                collections.insert(OiOwnedStory(storyId: receipt.id, createdAt: nil), at: 0)
            } else if action == "remove_collection" {
                collections.removeAll { $0.storyId == receipt.id }; favorites.remove(receipt.id)
            } else if action == "favorite", let enabled = payload["enabled"] as? Bool {
                if enabled { favorites.insert(receipt.id) } else { favorites.remove(receipt.id) }
            }
        }
        revision += 1
    }

    private func change<Value: Decodable>(_ action: String, payload: [String: Any], as type: Value.Type) async -> Value? {
        guard !isBusy else { return nil }
        isBusy = true; error = nil
        defer { isBusy = false }
        let started = generation
        do {
            guard let api else { throw OiServiceError.configuration }
            let response = try await api.mutate(action, payload: payload, token: token(), as: type)
            guard started == generation else { throw OiServiceError.accountChanged }
            applyReceipt(response, action: action, payload: payload)
            await refreshAfterCommit()
            return response
        } catch { if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription }; return nil }
    }

    func perform(_ action: String, payload: [String: Any]) async {
        if ["reopen_story","delete_story","review_story","submit_story"].contains(action) {
            _ = await change(action, payload: payload, as: OiLiveStory.self)
        } else if ["review_evidence","submit_evidence","reopen_evidence"].contains(action) {
            _ = await change(action, payload: payload, as: OiEvidence.self)
        } else { _ = await change(action, payload: payload, as: OiMutationID.self) }
    }

    func save(_ draft: OiStoryDraft) async -> OiLiveStory? {
        guard canStartStory else { error = OiServiceError.storyCreationUnavailable.localizedDescription; return nil }
        do { return await change("save_story", payload: try draft.payload(), as: OiLiveStory.self) }
        catch { self.error = error.localizedDescription; return nil }
    }

    func submitStory(_ story: OiLiveStory, cucumber: OiCucumberPublication? = nil,
                     card: OiStoryCardPublication? = nil) async -> OiLiveStory? {
        guard canStartStory else { error = OiServiceError.storyCreationUnavailable.localizedDescription; return nil }
        var payload: [String: Any] = ["id": story.id.uuidString, "revision": story.revision]
        guard cucumber == nil || canPublishCucumberAppearance else {
            error = "서버가 꾸민 오이의 공개를 지원할 때 다시 요청해 주세요. 내 지도와 초안은 저장돼 있어요."
            return nil
        }
        guard card == nil || canPublishStoryCard else {
            error = "서버가 꾸민 카드의 공개를 지원할 때 다시 요청해 주세요. 내 카드와 초안은 저장돼 있어요."
            return nil
        }
        guard !isBusy, let api, account?.id == story.userId else { return nil }
        let started = generation
        let expectedAppearance = cucumber?.appearance ?? story.cucumberAppearance
        let expectedCard = card?.id ?? story.cardSnapshotId
        func confirmsSubmission(_ result: OiLiveStory) -> Bool {
            result.id == story.id && result.userId == story.userId && result.status == "pending" &&
            result.revision == story.revision + 1 && result.cucumberAppearance == expectedAppearance &&
            result.cardSnapshotId == expectedCard
        }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let accessToken = try await token()
            let storageOwner = story.storageOwnerId ?? story.userId
            if let cucumber, cucumber.appearance != story.cucumberAppearance {
                let reference = OiCucumberArtworkReference(ownerID: storageOwner, storyID: story.id, appearance: cucumber.appearance)
                for part in reference.parts {
                    try Task.checkCancellation()
                    guard started == generation, let data = cucumber.images[part] else { throw OiServiceError.accountChanged }
                    try await api.upload(bucket: OiPublishedCucumberImage.bucket, path: reference.path(part),
                                         data: data, contentType: "image/png", token: accessToken)
                }
                payload["cucumber_appearance"] = cucumber.appearance.payload
            }
            if let card, card.id != story.cardSnapshotId {
                try Task.checkCancellation()
                guard started == generation else { throw OiServiceError.accountChanged }
                let path = StoryCard.artworkPath(owner: storageOwner, story: story.id, snapshot: card.id)
                try await api.upload(bucket: OiPublishedCucumberImage.bucket, path: path,
                                     data: card.png, contentType: "image/png", token: accessToken)
                payload["card_snapshot_id"] = card.id.uuidString.lowercased()
            }
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            let receipt: OiLiveStory
            do {
                receipt = try await api.mutate("submit_story", payload: payload, token: accessToken, as: OiLiveStory.self)
            } catch URLError.timedOut {
                let rows = try? await api.rows("oi_stories", query: "id=eq.\(story.id.uuidString)&user_id=eq.\(story.userId.uuidString)",
                                              token: accessToken, as: OiLiveStory.self)
                try Task.checkCancellation()
                guard let confirmed = rows?.first, confirmsSubmission(confirmed) else {
                    throw OiServiceError.server("검토 요청 접수를 확인하지 못했어요. 연결을 확인하고 다시 요청해 주세요.")
                }
                receipt = confirmed
            }
            guard started == generation else { throw OiServiceError.accountChanged }
            guard confirmsSubmission(receipt) else { throw OiServiceError.unavailable }
            applyReceipt(receipt, action: "submit_story", payload: payload)
            await refreshAfterCommit()
            guard started == generation else { return nil }
            return receipt
        } catch {
            if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription }
            return nil
        }
    }

    func updateProfile(nickname: String? = nil, schoolID: String? = nil, academicInfo: OiPublicAcademicInfo? = nil) async {
        guard !isBusy, !needsReauthentication, let account, let api else { error = OiServiceError.signInRequired.localizedDescription; return }
        let owner = account.id
        let started = generation
        let cleaned = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != nil || schoolID != nil || academicInfo != nil,
              academicInfo?.cleaned.isValid ?? true,
              cleaned.map({ !$0.isEmpty && $0.count <= 30 }) ?? true,
              schoolID == nil || schools.contains(where: { $0.id == schoolID }) else {
            error = OiServiceError.invalidInput.localizedDescription; return
        }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            var saved = try await api.updateProfile(owner: owner, nickname: cleaned, schoolID: schoolID, academicInfo: academicInfo, token: token())
            guard started == generation, self.account?.id == owner else { return }
            saved.schoolAdmissionYear = saved.schoolId == profile?.schoolId ? profile?.schoolAdmissionYear : nil
            saved.schoolDepartment = saved.schoolId == profile?.schoolId ? profile?.schoolDepartment : nil
            loadSequence += 1
            profile = saved; revision += 1; await refreshAfterCommit()
        } catch { if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription } }
    }

    func saveFarmerOutfit(_ outfit: OiFarmerOutfit) async -> Bool {
        guard !isBusy, !needsReauthentication, let account, let api else {
            error = OiServiceError.signInRequired.localizedDescription; return false
        }
        guard isFarmerOutfitAvailable else {
            error = "지금은 농부 꾸미기를 저장할 수 없어요. 잠시 후 다시 시도해 주세요."; return false
        }
        guard outfit.isValid else { error = OiServiceError.invalidInput.localizedDescription; return false }
        let owner = account.id
        let started = generation
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation, self.account?.id == owner else { return false }
            let saved = try await api.saveFarmerOutfit(owner: owner, outfit: outfit, token: accessToken)
            try Task.checkCancellation()
            guard started == generation, self.account?.id == owner else { return false }
            loadSequence += 1
            farmerOutfit = saved; revision += 1
            await refreshAfterCommit()
            return started == generation && self.account?.id == owner
        } catch {
            if started == generation, !Task.isCancelled, !OiServiceFailure.isCancellation(error) {
                noteAuthenticationFailure(error); self.error = error.localizedDescription
            }
            return false
        }
    }

    func updateFarmName(_ name: String) async {
        guard !isBusy, !needsReauthentication, let account, let api else { error = OiServiceError.signInRequired.localizedDescription; return }
        guard profile?.farmName != nil else {
            error = "지금은 농장 이름을 저장할 수 없어요. 잠시 후 다시 시도해 주세요."; return
        }
        let owner = account.id
        let started = generation
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !cleaned.isEmpty, cleaned.unicodeScalars.count <= 6 else {
            error = OiServiceError.invalidInput.localizedDescription; return
        }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation, self.account?.id == owner else { return }
            var saved = try await api.updateFarmName(owner: owner, farmName: cleaned, token: accessToken)
            try Task.checkCancellation()
            guard started == generation, self.account?.id == owner else { return }
            saved.schoolAdmissionYear = saved.schoolId == profile?.schoolId ? profile?.schoolAdmissionYear : nil
            saved.schoolDepartment = saved.schoolId == profile?.schoolId ? profile?.schoolDepartment : nil
            loadSequence += 1
            profile = saved; revision += 1; await refreshAfterCommit()
        } catch {
            if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription }
        }
    }

    func updateSchoolProfile(schoolID: String, admissionYear: Int, department: String?) async {
        guard !isBusy, !needsReauthentication, let account, let api else { error = OiServiceError.signInRequired.localizedDescription; return }
        guard isSchoolProfileAvailable else { error = "지금은 학교 정보를 저장할 수 없어요. 잠시 후 다시 시도해 주세요."; return }
        let owner = account.id
        let started = generation
        let cleanedDepartment = department?.trimmingCharacters(in: .whitespacesAndNewlines)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let currentYear = calendar.component(.year, from: .now)
        guard schools.contains(where: { $0.id == schoolID }), (1900...currentYear).contains(admissionYear),
              cleanedDepartment.map({ !$0.isEmpty && $0.unicodeScalars.count <= 100 }) ?? true else {
            error = OiServiceError.invalidInput.localizedDescription; return
        }
        isBusy = true; error = nil
        defer { if started == generation { isBusy = false } }
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation else { return }
            let saved = try await api.updateSchoolProfile(owner: owner, schoolID: schoolID,
                admissionYear: admissionYear, department: cleanedDepartment, token: accessToken)
            guard started == generation, self.account?.id == owner else { return }
            loadSequence += 1
            profile = saved
            if let index = profiles.firstIndex(where: { $0.id == owner }) {
                profiles[index].schoolId = saved.schoolId
            }
            revision += 1
        } catch {
            if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription }
        }
    }

    func submitEvidence(data: Data, contentType: String, fileExtension: String, replacing request: OiEvidence? = nil,
                        operatorAIConsent: Bool = false) async {
        guard !isBusy, !needsReauthentication, let owner = account?.id else { error = OiServiceError.signInRequired.localizedDescription; return }
        let started = generation
        do {
            let operation = OiEvidenceOperation(requestID: request?.id ?? UUID(), uploadID: UUID(), contentType: contentType,
                fileExtension: fileExtension, previousStatus: request?.status, previousPath: request?.objectPath, phase: "prepared",
                storageOwnerID: request?.storageOwnerId ?? request?.userId, operatorAIConsent: operatorAIConsent)
            try await drafts.saveAttachment(data, owner: owner, id: operation.uploadID)
            try await drafts.saveEvidence(operation, owner: owner)
            try Task.checkCancellation()
            guard generation == started, account?.id == owner else { throw OiServiceError.accountChanged }
            evidenceOperation = operation; await retryEvidence()
        } catch { if generation == started { self.error = error.localizedDescription } }
    }

    func retryEvidence() async {
        guard !isBusy, let api, let owner = account?.id, var operation = evidenceOperation else { return }
        let started = generation
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard generation == started else { throw OiServiceError.accountChanged }
            var request = try await api.mutate("start_evidence", payload: ["id":operation.requestID.uuidString], token: accessToken, as: OiEvidence.self)
            guard generation == started else { throw OiServiceError.accountChanged }
            operation.storageOwnerID = request.storageOwnerId ?? request.userId
            try await drafts.saveEvidence(operation, owner: owner)
            guard generation == started else { throw OiServiceError.accountChanged }
            evidenceOperation = operation
            let path = operation.objectPath(owner: owner)
            if request.objectPath == path && request.status != "draft" { operation.phase = request.status }
            else {
                if let previousStatus = operation.previousStatus, let previousPath = operation.previousPath {
                    request = try await api.mutate("reopen_evidence", payload: ["id":request.id.uuidString,"operation_id":operation.uploadID.uuidString,
                        "expected_status":previousStatus,"expected_object_path":previousPath], token: accessToken, as: OiEvidence.self)
                    guard generation == started else { throw OiServiceError.accountChanged }
                }
                guard request.status == "draft" else { throw OiServiceError.conflict }
                operation.phase = "uploading"; try await drafts.saveEvidence(operation, owner: owner)
                guard generation == started else { throw OiServiceError.accountChanged }
                evidenceOperation = operation
                let data = try await drafts.attachment(owner: owner, id: operation.uploadID)
                try Task.checkCancellation()
                guard generation == started else { throw OiServiceError.accountChanged }
                try await api.upload(bucket: "oi-evidence", path: path, data: data, contentType: operation.contentType, token: accessToken)
                guard generation == started else { throw OiServiceError.accountChanged }
                operation.phase = "submitting"; try await drafts.saveEvidence(operation, owner: owner)
                guard generation == started else { throw OiServiceError.accountChanged }
                evidenceOperation = operation
                request = try await api.mutate("submit_evidence", payload: ["id": request.id.uuidString, "object_path": path,
                    "operator_ai_consent": operation.operatorAIConsent == true], token: accessToken, as: OiEvidence.self)
                operation.phase = request.status
            }
            guard generation == started else { throw OiServiceError.accountChanged }
            applyReceipt(request, action: "submit_evidence", payload: [:]); evidenceOperation = operation
            do { try await drafts.saveEvidence(operation, owner: owner) }
            catch { syncWarning = "제출은 완료됐지만 기기의 제출 상태 기록에 실패했습니다. 서버 상태를 새로 확인해 주세요." }
            await refreshAfterCommit()
        } catch {
            guard generation == started else { return }
            noteAuthenticationFailure(error); operation.phase = "failed"; operation.failure = error.localizedDescription
            evidenceOperation = operation; self.error = error.localizedDescription
            do { try await drafts.saveEvidence(operation, owner: owner) }
            catch { self.error = "제출 재시도 정보를 기기에 보관하지 못했습니다. \(error.localizedDescription)" }
        }
    }

    func uploadStoryImage(_ data: Data, photoID: UUID, story: OiLiveStory) async -> OiLiveStory? {
        guard !isBusy, let api, account?.id == story.userId else { return nil }
        let started = generation
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let accessToken = try await token()
            let path = "\((story.storageOwnerId ?? story.userId).uuidString.lowercased())/\(story.id.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
            try await api.upload(bucket: "oi-story-media", path: path, data: data, contentType: "image/jpeg", token: accessToken)
            let currentMedia = try await api.rows("oi_story_media", query: "story_id=eq.\(story.id.uuidString)&order=position.asc", token: accessToken, as: OiMedia.self)
            var paths = currentMedia.map(\.objectPath)
            if !paths.contains(path) { paths.append(path) }
            let updated = try await api.mutate("attach_media", payload: ["id":story.id.uuidString,"revision":story.revision,"paths":paths], token: accessToken, as: OiLiveStory.self)
            guard started == generation else { throw OiServiceError.accountChanged }
            committedMediaPaths[story.id] = paths
            applyReceipt(updated, action: "attach_media", payload: [:]); await refreshAfterCommit()
            return updated
        } catch { if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription }; return nil }
    }

    func setStoryMedia(_ paths: [String], story: OiLiveStory) async -> OiLiveStory? {
        guard !isBusy, let api else { return nil }
        let started = generation
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let updated = try await api.mutate("attach_media", payload: ["id": story.id.uuidString,
                "revision": story.revision, "paths": paths], token: token(), as: OiLiveStory.self)
            guard started == generation else { throw OiServiceError.accountChanged }
            committedMediaPaths[story.id] = paths
            applyReceipt(updated, action: "attach_media", payload: [:])
            await refreshAfterCommit()
            guard started == generation else { return nil }
            return updated
        } catch {
            if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription }
            return nil
        }
    }

    func removeStoryMedia(paths removedPaths: Set<String>, photoIDs removedPhotoIDs: Set<UUID>, story: OiLiveStory) async -> OiLiveStory? {
        guard !isBusy, !needsReauthentication, let api, account?.id == story.userId else { return nil }
        let started = generation
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let accessToken = try await token()
            let current = try await api.rows("oi_story_media", query: "story_id=eq.\(story.id.uuidString)&order=position.asc,id.asc",
                token: accessToken, as: OiMedia.self).map(\.objectPath)
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            let retained = current.filter { path in
                if removedPaths.contains(path) { return false }
                guard let leaf = path.split(separator: "/").last, leaf.lowercased().hasSuffix(".jpg"),
                      let id = UUID(uuidString: String(leaf.dropLast(4))) else { return true }
                return !removedPhotoIDs.contains(id)
            }
            if current == retained {
                // The server already reflects the removal. Replace a stale cached list.
                loadSequence += 1
                committedMediaPaths[story.id] = retained
                revision += 1
                return story
            }
            let updated = try await api.mutate("attach_media", payload: ["id": story.id.uuidString,
                "revision": story.revision, "paths": retained], token: accessToken, as: OiLiveStory.self)
            guard started == generation else { throw OiServiceError.accountChanged }
            committedMediaPaths[story.id] = retained
            applyReceipt(updated, action: "attach_media", payload: [:])
            await refreshAfterCommit()
            return started == generation ? updated : nil
        } catch {
            if started == generation, !OiServiceFailure.isCancellation(error) {
                noteAuthenticationFailure(error); self.error = error.localizedDescription
            }
            return nil
        }
    }

    func mediaPaths(storyID: UUID) -> [String] {
        committedMediaPaths[storyID] ?? media.filter { $0.storyId == storyID }.sorted { $0.position < $1.position }.map(\.objectPath)
    }

    func localDrafts() async throws -> [OiLocalDraft] {
        guard let owner = account?.id else { return [] }
        let values = try await drafts.list(owner: owner)
        guard owner == account?.id else { throw OiServiceError.accountChanged }; return values
    }

    func localDraftListing() async throws -> OiDraftListing {
        guard let owner = account?.id else { return OiDraftListing(drafts: [], unreadableFiles: [], pendingDiscardCount: 0) }
        let listing = try await drafts.listing(owner: owner)
        guard owner == account?.id else { throw OiServiceError.accountChanged }
        return listing
    }

    func localDraft(id: UUID, owner: UUID) async throws -> OiLocalDraft? {
        guard account?.id == owner else { throw OiServiceError.accountChanged }
        let record = try await drafts.load(owner: owner, id: id)
        guard account?.id == owner else { throw OiServiceError.accountChanged }; return record
    }

    func saveLocalDraft(_ record: OiLocalDraft, owner: UUID) async throws {
        guard account?.id == owner else { throw OiServiceError.accountChanged }
        try await drafts.save(record, owner: owner)
        guard account?.id == owner else { throw OiServiceError.accountChanged }
    }

    func savePersonalPlacement(_ record: OiLocalDraft, owner: UUID) async throws {
        guard canPlaceOi, account?.id == owner else { throw OiServiceError.signInRequired }
        guard record.personalPlacement != nil else { throw OiServiceError.invalidInput }
        let started = generation
        guard try await drafts.save(record, owner: owner) else { throw OiServiceError.conflict }
        guard started == generation, canPlaceOi, account?.id == owner else { throw OiServiceError.accountChanged }
        localPlacementRevision += 1
    }

    func discardLocalDraft(id: UUID, owner: UUID) async throws {
        guard account?.id == owner else { throw OiServiceError.accountChanged }
        let started = generation
        defer {
            if started == generation { localPlacementRevision += 1 }
        }
        try await drafts.discard(owner: owner, id: id)
    }

    func saveLocalPhoto(_ data: Data, id: UUID, owner: UUID) async throws {
        guard account?.id == owner else { throw OiServiceError.accountChanged }; try await drafts.saveAttachment(data, owner: owner, id: id)
    }

    func localPhoto(id: UUID, owner: UUID) async throws -> Data {
        guard account?.id == owner else { throw OiServiceError.accountChanged }
        let data = try await drafts.attachment(owner: owner, id: id)
        guard account?.id == owner else { throw OiServiceError.accountChanged }; return data
    }

    func localSchoolEvidenceReview(owner: UUID) async throws -> OiSavedSchoolEvidenceReview? {
        guard account?.id == owner else { throw OiServiceError.accountChanged }
        let started = generation
        let review = try await drafts.schoolEvidenceReview(owner: owner)
        try Task.checkCancellation()
        guard started == generation, account?.id == owner else { throw OiServiceError.accountChanged }
        return review
    }

    func saveSchoolEvidenceReview(_ review: OiSavedSchoolEvidenceReview, owner: UUID) async throws {
        try Task.checkCancellation()
        guard account?.id == owner else { throw OiServiceError.accountChanged }
        let started = generation
        try await drafts.saveSchoolEvidenceReview(review, owner: owner)
        try Task.checkCancellation()
        guard started == generation, account?.id == owner else { throw OiServiceError.accountChanged }
    }

    func reviewDonationEvidence(_ evidence: OiEvidence) async throws -> OiDonationEvidenceReview {
        guard let api else { throw OiServiceError.configuration }
        guard let owner = account?.id, owner == evidence.userId, !needsReauthentication else { throw OiServiceError.signInRequired }
        let started = generation
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            let review = try await api.reviewDonationEvidence(evidence, token: accessToken)
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            return review
        } catch {
            guard started == generation else { throw OiServiceError.accountChanged }
            noteAuthenticationFailure(error)
            throw error
        }
    }

    func reviewSchoolEvidence(_ data: Data, contentType: String) async throws -> OiSchoolEvidenceOutcome {
        guard let api else { throw OiServiceError.configuration }
        guard account != nil, !needsReauthentication else { throw OiServiceError.signInRequired }
        let started = generation
        do {
            let accessToken = try await token()
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            let review = try await api.reviewSchoolEvidence(data, contentType: contentType, token: accessToken)
            try Task.checkCancellation()
            guard started == generation else { throw OiServiceError.accountChanged }
            return review
        } catch {
            guard started == generation else { throw OiServiceError.accountChanged }
            noteAuthenticationFailure(error)
            throw error
        }
    }

    func mediaURL(bucket: String, path: String) async throws -> URL {
        guard let api else { throw OiServiceError.configuration }
        let started = generation
        let accessToken = account == nil ? nil : try await token()
        let url = try await api.signedURL(bucket: bucket, path: path, token: accessToken)
        guard started == generation else { throw OiServiceError.accountChanged }
        return url
    }

    func cucumberImage(_ path: String, part: OiCucumberArtworkReference.Part = .portrait) async throws -> UIImage {
        guard let api else { throw OiServiceError.configuration }
        let started = generation
        let accessToken = account == nil ? nil : try await token()
        let bytes = try await api.downloadSignedObject(bucket: OiPublishedCucumberImage.bucket, path: path, token: accessToken)
        try Task.checkCancellation()
        guard started == generation else { throw OiServiceError.accountChanged }
        return UIImage(cgImage: try OiPublishedCucumberImage.decode(bytes, part: part))
    }
}
