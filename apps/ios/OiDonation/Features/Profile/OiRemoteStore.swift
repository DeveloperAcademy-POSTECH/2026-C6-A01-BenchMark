// Created by 이돈혁

import Foundation
import Observation

@MainActor @Observable
final class OiRemoteStore: OiOperatorStoryServing, OiOperatorEvidenceServing, OiOperatorEvidenceHistoryServing, OiOperatorEvidenceAnalysisServing, OiOperatorAuditServing {
    private(set) var schools: [OiSchool] = []
    private(set) var regions: [OiRegion] = []
    private(set) var assets: [OiAsset] = []
    private(set) var account: OiAccount?
    private(set) var profile: OiProfile?
    private(set) var stories: [OiLiveStory] = []
    private(set) var ownStories: [OiLiveStory] = []
    private(set) var reviewStories: [OiLiveStory] = []
    private(set) var profiles: [OiProfile] = []
    private(set) var media: [OiMedia] = []
    private(set) var evidence: [OiEvidence] = []
    private(set) var grants: [OiWritingGrant] = []
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
    private(set) var isConfigured = false
    private(set) var isAccountMergeAvailable = false
    private(set) var accountMemberIDs: Set<UUID> = []
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
        profile = nil; ownStories = []; reviewStories = []; profiles = []; media = []; evidence = []; grants = []
        stories = []; collections = []; favorites = []; collectionCounts = [:]; evidenceOperation = nil; committedMediaPaths = [:]
        isOperator = false; hasLoadedRemote = false; needsReauthentication = false; isRefreshing = false
        isAccountMergeAvailable = false; accountMemberIDs = []; accountProviders = []; localRecoveryWarning = nil
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
            let (receipt, revokedGrantIDs) = try await withOperatorSession { api, token in
                let grants = review.decision == .revoked
                    ? try await api.rows("oi_writing_grants", query: "evidence_id=eq.\(review.snapshot.id.uuidString)", token: token, as: OiWritingGrant.self) : []
                return (try await api.reviewEvidence(review, token: token), Set(grants.map(\.id)))
            }
            guard started == generation else { throw OiServiceError.accountChanged }
            guard receipt.id == review.snapshot.id, receipt.status == review.decision.rawValue,
                  receipt.objectPath == review.snapshot.objectPath, receipt.userId == review.snapshot.userId,
                  receipt.reviewedAt != nil else { throw OiOperatorStoryError.unconfirmedResult }
            applyReceipt(receipt, action: "review_evidence", payload: [:])
            if review.decision == .revoked {
                // Remove affected cached entries even if synchronization fails.
                stories.removeAll { revokedGrantIDs.contains($0.grantId) }
                reviewStories.removeAll { revokedGrantIDs.contains($0.grantId) }
                ownStories.removeAll { revokedGrantIDs.contains($0.grantId) }
                grants.removeAll { revokedGrantIDs.contains($0.id) }
            }
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
            let receipt = try await api.mutate("review_story", payload: ["id": story.id.uuidString,
                "revision": story.revision, "status": wanted], token: accessToken, as: OiLiveStory.self)
            guard started == generation else { throw OiServiceError.accountChanged }
            guard receipt.id == story.id, receipt.status == wanted, receipt.revision > story.revision else {
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

    func cardRequests() async throws -> [OiCardRequest] {
        try await withCardRequestSession { api, token in try await api.cardRequests(token: token) }
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
        return try await api.publishedStory(id)
    }

    func publishedStories() async throws -> [OiLiveStory] {
        guard let api else { throw OiServiceError.configuration }
        return try await api.publishedStories()
    }

    func campusStory(_ item: OiLiveStory, order: Int = 0) -> CampusStory {
        var story = CampusStory(id: item.id.uuidString, regionID: item.regionId, title: item.cucumberName,
            image: item.cucumberAsset, tags: [item.theme, item.emotion],
            donor: profiles.first { $0.id == item.userId }?.nickname ?? "작성자 정보 확인 중",
            location: regions.first { $0.id == item.regionId }?.name ?? "POSTECH",
            date: item.createdDateLabel, order: order, popularity: collectionCounts[item.id] ?? 0, palette: 0)
        story.remoteBody = item.body
        story.remoteMediaPaths = mediaPaths(storyID: item.id)
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
        if let accessToken { capabilities = try await api.capabilities(token: accessToken) }
        else { capabilities = nil }
        let resolvedOwner = capabilities?.accountId ?? account?.id
        let members = Set(capabilities?.accountMemberIds ?? resolvedOwner.map { [$0] } ?? [])
        let fetchedSchools = try await api.rows("oi_schools", query: "order=id.asc", as: OiSchool.self)
        let fetchedRegions = try await api.rows("oi_regions", query: "order=id.asc", as: OiRegion.self)
        let fetchedAssets = try await api.rows("oi_assets", query: "order=id.asc", as: OiAsset.self)
        let fetched = try await api.rows("oi_stories", query: "order=created_at.desc,id.asc", token: accessToken, as: OiLiveStory.self)
        let fetchedProfiles = try await api.rows("oi_profiles", token: accessToken, as: OiProfile.self)
        let fetchedMedia = try await api.rows("oi_story_media", query: "order=position.asc,id.asc", token: accessToken, as: OiMedia.self)
        let metrics = try await api.collectionMetrics(token: accessToken)
        var requests: [OiEvidence] = []; var permissions: [OiWritingGrant] = []
        var collected: [OiOwnedStory] = []; var starred: [OiOwnedStory] = []
        if let accessToken {
            requests = try await api.rows("oi_evidence_requests", query: "order=created_at.desc", token: accessToken, as: OiEvidence.self)
            permissions = try await api.rows("oi_writing_grants", query: "user_id=eq.\(resolvedOwner?.uuidString ?? "")", token: accessToken, as: OiWritingGrant.self)
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
        stories = fetched.filter { $0.status == "published" }
        ownStories = fetched.filter { $0.userId == account?.id && $0.status != "deleted" }
        reviewStories = capabilities?.operator == true ? fetched.filter { ["pending","published","hidden"].contains($0.status) } : []
        profile = fetchedProfiles.first { $0.id == account?.id }
        profiles = fetchedProfiles; media = fetchedMedia; evidence = requests; grants = permissions; committedMediaPaths = [:]
        collections = collected; favorites = Set(starred.map(\.storyId)); isOperator = capabilities?.operator == true
        isAccountMergeAvailable = capabilities?.accountMergeEnabled == true; accountMemberIDs = members
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
            ownStories.removeAll { $0.id == story.id }; stories.removeAll { $0.id == story.id }; reviewStories.removeAll { $0.id == story.id }
            if story.userId == account?.id && story.status != "deleted" { ownStories.insert(story, at: 0) }
            if story.status == "published" { stories.insert(story, at: 0) }
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
        do { return await change("save_story", payload: try draft.payload(), as: OiLiveStory.self) }
        catch { self.error = error.localizedDescription; return nil }
    }

    func submitStory(_ story: OiLiveStory) async -> OiLiveStory? {
        await change("submit_story", payload: ["id":story.id.uuidString,"revision":story.revision], as: OiLiveStory.self)
    }

    func updateProfile(nickname: String? = nil, schoolID: String? = nil) async {
        guard !isBusy, !needsReauthentication, let account, let api else { error = OiServiceError.signInRequired.localizedDescription; return }
        let owner = account.id
        let started = generation
        let cleaned = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != nil || schoolID != nil,
              cleaned.map({ !$0.isEmpty && $0.count <= 30 }) ?? true,
              schoolID == nil || schools.contains(where: { $0.id == schoolID }) else {
            error = OiServiceError.invalidInput.localizedDescription; return
        }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let saved = try await api.updateProfile(owner: owner, nickname: cleaned, schoolID: schoolID, token: token())
            guard started == generation, self.account?.id == owner else { return }
            loadSequence += 1
            profile = saved; revision += 1; await refreshAfterCommit()
        } catch { if started == generation { noteAuthenticationFailure(error); self.error = error.localizedDescription } }
    }

    func submitEvidence(data: Data, contentType: String, fileExtension: String, replacing request: OiEvidence? = nil) async {
        guard !isBusy, let owner = account?.id else { error = OiServiceError.signInRequired.localizedDescription; return }
        do {
            let operation = OiEvidenceOperation(requestID: request?.id ?? UUID(), uploadID: UUID(), contentType: contentType,
                fileExtension: fileExtension, previousStatus: request?.status, previousPath: request?.objectPath, phase: "prepared",
                storageOwnerID: request?.storageOwnerId ?? request?.userId)
            try await drafts.saveAttachment(data, owner: owner, id: operation.uploadID)
            try await drafts.saveEvidence(operation, owner: owner)
            guard account?.id == owner else { throw OiServiceError.accountChanged }
            evidenceOperation = operation; await retryEvidence()
        } catch { self.error = error.localizedDescription }
    }

    func retryEvidence() async {
        guard !isBusy, let api, let owner = account?.id, var operation = evidenceOperation else { return }
        let started = generation
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let accessToken = try await token()
            var request = try await api.mutate("start_evidence", payload: ["id":operation.requestID.uuidString], token: accessToken, as: OiEvidence.self)
            operation.storageOwnerID = request.storageOwnerId ?? request.userId
            try await drafts.saveEvidence(operation, owner: owner)
            evidenceOperation = operation
            let path = operation.objectPath(owner: owner)
            if request.objectPath == path && request.status != "draft" { operation.phase = request.status }
            else {
                if let previousStatus = operation.previousStatus, let previousPath = operation.previousPath {
                    request = try await api.mutate("reopen_evidence", payload: ["id":request.id.uuidString,"operation_id":operation.uploadID.uuidString,
                        "expected_status":previousStatus,"expected_object_path":previousPath], token: accessToken, as: OiEvidence.self)
                }
                guard request.status == "draft" else { throw OiServiceError.conflict }
                operation.phase = "uploading"; try await drafts.saveEvidence(operation, owner: owner); evidenceOperation = operation
                let data = try await drafts.attachment(owner: owner, id: operation.uploadID)
                try await api.upload(bucket: "oi-evidence", path: path, data: data, contentType: operation.contentType, token: accessToken)
                operation.phase = "submitting"; try await drafts.saveEvidence(operation, owner: owner); evidenceOperation = operation
                request = try await api.mutate("submit_evidence", payload: ["id":request.id.uuidString,"object_path":path], token: accessToken, as: OiEvidence.self)
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
        guard !isBusy, let api, let owner = account?.id else { return nil }
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

    func discardLocalDraft(id: UUID, owner: UUID) async throws {
        guard account?.id == owner else { throw OiServiceError.accountChanged }; try await drafts.discard(owner: owner, id: id)
    }

    func saveLocalPhoto(_ data: Data, id: UUID, owner: UUID) async throws {
        guard account?.id == owner else { throw OiServiceError.accountChanged }; try await drafts.saveAttachment(data, owner: owner, id: id)
    }

    func localPhoto(id: UUID, owner: UUID) async throws -> Data {
        guard account?.id == owner else { throw OiServiceError.accountChanged }
        let data = try await drafts.attachment(owner: owner, id: id)
        guard account?.id == owner else { throw OiServiceError.accountChanged }; return data
    }

    func mediaURL(bucket: String, path: String) async throws -> URL {
        guard let api else { throw OiServiceError.configuration }
        let started = generation
        let accessToken = account == nil ? nil : try await token()
        let url = try await api.signedURL(bucket: bucket, path: path, token: accessToken)
        guard started == generation else { throw OiServiceError.accountChanged }
        return url
    }
}
