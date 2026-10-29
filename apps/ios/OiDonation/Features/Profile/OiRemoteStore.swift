// Created by 이돈혁

import Foundation
import Observation

@MainActor @Observable
final class OiRemoteStore {
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
    var error: String?
    private var api: OiServiceAPI?
    private var session: OiSession?
    private var refreshTask: Task<OiSession, Error>?
    private var generation = UUID()
    private var loadSequence = 0
    private var committedMediaPaths: [UUID:[String]] = [:]
    private let authentication = OiGoogleAuthentication()
    private let drafts: OiDraftVault
    private let vault: any OiSessionStorage

    init(api: OiServiceAPI? = nil, drafts: OiDraftVault = OiDraftVault(), vault: (any OiSessionStorage)? = nil) {
        self.api = api; self.drafts = drafts; self.vault = vault ?? OiSessionVault()
    }

    func start() async {
        do {
            if api == nil { api = try OiServiceAPI.configured() }
            isConfigured = true
            let restored = try vault.read()
            if restored?.user.id != account?.id { resetAccountState() }
            session = restored; account = restored?.user
            if let owner = account?.id {
                let operation = try await drafts.evidence(owner: owner)
                guard owner == account?.id else { throw OiServiceError.accountChanged }
                evidenceOperation = operation
            }
            await refresh()
        } catch { loadError = error.localizedDescription; self.error = error.localizedDescription }
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
            let updated = try await refresh.value
            guard started == generation, updated.user.id == current.user.id else { throw OiServiceError.accountChanged }
            try vault.write(updated); session = updated; refreshTask = nil
            return updated.accessToken
        } catch { if started == generation { refreshTask = nil }; throw error }
    }

    func signIn() async {
        guard !isBusy, let api else { error = OiServiceError.configuration.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await authentication.signIn(api: api)
            try vault.write(updated); resetAccountState(); session = updated; account = updated.user
            evidenceOperation = try await drafts.evidence(owner: updated.user.id)
            do { try await load() } catch { loadError = error.localizedDescription; noteAuthenticationFailure(error) }
        } catch { self.error = error.localizedDescription }
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
            if let oldToken, let api { _ = try await api.request("auth/v1/logout", method: "POST", token: oldToken) }
        } catch { syncWarning = "이 기기는 로그아웃했지만 서버 세션 정리는 확인하지 못했습니다. \(error.localizedDescription)" }
        do { try await load() } catch { loadError = error.localizedDescription }
    }

    private func resetAccountState() {
        generation = UUID(); loadSequence += 1; refreshTask?.cancel(); refreshTask = nil
        profile = nil; ownStories = []; reviewStories = []; profiles = []; media = []; evidence = []; grants = []
        stories = []; collections = []; favorites = []; collectionCounts = [:]; evidenceOperation = nil; committedMediaPaths = [:]
        isOperator = false; hasLoadedRemote = false; needsReauthentication = false; isRefreshing = false
        loadError = nil; syncWarning = nil; error = nil; revision += 1
    }

    private func noteAuthenticationFailure(_ error: Error) {
        if case OiServiceError.signInRequired = error, account != nil { needsReauthentication = true }
    }

    func refresh() async {
        guard !isBusy, !isRefreshing else { return }
        let started = generation
        isRefreshing = true
        defer { if started == generation { isRefreshing = false } }
        do { try await load() }
        catch is CancellationError {}
        catch { if started == generation { loadError = error.localizedDescription; noteAuthenticationFailure(error) } }
    }

    /// Always query as the public role so even an owner cannot render a hidden story in AR.
    func publishedStory(_ id: UUID) async throws -> OiLiveStory {
        guard let api else { throw OiServiceError.configuration }
        return try await api.publishedStory(id)
    }

    private func load() async throws {
        guard let api else { throw OiServiceError.configuration }
        let started = generation
        loadSequence += 1
        let sequence = loadSequence
        let accessToken = account == nil ? nil : try await token()
        let fetched = try await api.rows("oi_stories", query: "order=created_at.desc,id.asc", token: accessToken, as: OiLiveStory.self)
        let fetchedProfiles = try await api.rows("oi_profiles", token: accessToken, as: OiProfile.self)
        let fetchedMedia = try await api.rows("oi_story_media", query: "order=position.asc,id.asc", token: accessToken, as: OiMedia.self)
        let metrics = try await api.collectionMetrics(token: accessToken)
        var requests: [OiEvidence] = []; var permissions: [OiWritingGrant] = []
        var collected: [OiOwnedStory] = []; var starred: [OiOwnedStory] = []; var capabilities = false
        if let accessToken {
            requests = try await api.rows("oi_evidence_requests", query: "order=created_at.desc", token: accessToken, as: OiEvidence.self)
            permissions = try await api.rows("oi_writing_grants", query: "user_id=eq.\(account?.id.uuidString ?? "")", token: accessToken, as: OiWritingGrant.self)
            collected = try await api.rows("oi_collections", query: "order=created_at.desc,story_id.asc", token: accessToken, as: OiOwnedStory.self)
            starred = try await api.rows("oi_favorites", token: accessToken, as: OiOwnedStory.self)
            capabilities = try await api.capabilities(token: accessToken).operator
        }
        guard started == generation, sequence == loadSequence else { throw CancellationError() }
        stories = fetched.filter { $0.status == "published" }
        ownStories = fetched.filter { $0.userId == account?.id && $0.status != "deleted" }
        reviewStories = capabilities ? fetched.filter { ["pending","published","hidden"].contains($0.status) } : []
        profile = fetchedProfiles.first { $0.id == account?.id }
        profiles = fetchedProfiles; media = fetchedMedia; evidence = requests; grants = permissions; committedMediaPaths = [:]
        collections = collected; favorites = Set(starred.map(\.storyId)); isOperator = capabilities
        collectionCounts = metrics.reduce(into: [:]) { $0[$1.storyId] = $1.collectionCount }
        hasLoadedRemote = true; needsReauthentication = false; loadError = nil; syncWarning = nil; revision += 1
    }

    private func refreshAfterCommit() async {
        do { try await load() }
        catch {
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

    func updateProfile(nickname: String) async {
        guard !isBusy, let account, let api else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do { profile = try await api.updateProfile(owner: account.id, nickname: nickname, token: token()); revision += 1; await refreshAfterCommit() }
        catch { noteAuthenticationFailure(error); self.error = error.localizedDescription }
    }

    func submitEvidence(data: Data, contentType: String, fileExtension: String, replacing request: OiEvidence? = nil) async {
        guard !isBusy, let owner = account?.id else { error = OiServiceError.signInRequired.localizedDescription; return }
        do {
            let operation = OiEvidenceOperation(requestID: request?.id ?? UUID(), uploadID: UUID(), contentType: contentType,
                fileExtension: fileExtension, previousStatus: request?.status, previousPath: request?.objectPath, phase: "prepared")
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
            let path = "\(owner.uuidString.lowercased())/\(story.id.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
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

    func mediaPaths(storyID: UUID) -> [String] {
        committedMediaPaths[storyID] ?? media.filter { $0.storyId == storyID }.sorted { $0.position < $1.position }.map(\.objectPath)
    }

    func localDrafts() async throws -> [OiLocalDraft] {
        guard let owner = account?.id else { return [] }
        let values = try await drafts.list(owner: owner)
        guard owner == account?.id else { throw OiServiceError.accountChanged }; return values
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
