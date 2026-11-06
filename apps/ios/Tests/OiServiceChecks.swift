//
//  OiServiceChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import Foundation

final class OiURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url, let handler = Self.handler else { throw OiServiceError.unavailable }
            let (status, data) = try handler(request)
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"]) else { throw OiServiceError.unavailable }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct OiServiceChecks {
    @MainActor static func checkFieldTrial() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trial.json")
        let repo = OiWardrobeFieldTrialRepository(url: url)
        let empty = try repo.load(); precondition(empty == nil)
        var look = OiWardrobeLook(); look.top = .hoodie; look.topColor = 0xB9DCD4
        look.fabrics["bottom-long"] = .allCases[0]
        let source = String(repeating: "a", count: 64), bytes = Data([1, 2, 3])
        var photo = OiPhotoLayer(source: source); photo.side = .back; photo.placement.rotation = 35
        try look.artwork.set(OiPhotoDesign(layers: [photo]), sources: [source: bytes], for: "top-hoodie")
        let trial = OiWardrobeFieldTrial(name: "현장 테스트", latitude: 36.012, longitude: 129.323, heading: 124, look: look)
        try repo.save(trial)
        let reopened = try OiWardrobeFieldTrialRepository(url: url).load()
        precondition(reopened == trial && OiWardrobeFieldTrial.heightMeters == 1.5)
        let original = try Data(contentsOf: url)
        var invalid = trial; invalid.latitude = .nan
        do { try repo.save(invalid); preconditionFailure("Invalid location accepted") } catch { }
        let unchanged = try Data(contentsOf: url); precondition(unchanged == original)
        var replacement = trial; replacement.look.costume = .dinosaur
        try repo.save(replacement)
        let replaced = try repo.load(); precondition(replaced == replacement)
        let corrupt = Data("damaged".utf8); try corrupt.write(to: url)
        do { try repo.save(trial); preconditionFailure("Damaged test overwritten") } catch { }
        let damaged = try Data(contentsOf: url); precondition(damaged == corrupt)
        try repo.remove(); let deleted = try repo.load(); precondition(deleted == nil)
        print("PASS: local field trial photo/denim/location relaunch, replacement, invalid-write rejection, damaged-file preservation and deletion")
    }

    static func checkSchoolReviewRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        let original = OiSavedSchoolEvidenceReview(
            summary: .init(outcome: "school_document_needed", title: "학교 발급 증빙 필요",
                           detail: "프로필 캡처가 제출됐어요.", nextStep: "학생증 앞면을 제출해 주세요.", reference: nil),
            reviewedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        try await OiDraftVault(directory: directory).saveSchoolEvidenceReview(original, owner: owner)

        let reopened = OiDraftVault(directory: directory)
        let restored = try await reopened.schoolEvidenceReview(owner: owner)
        let otherAccount = try await reopened.schoolEvidenceReview(owner: UUID())
        precondition(restored?.summary.outcome == original.summary.outcome)
        precondition(restored?.reviewedAt == original.reviewedAt && otherAccount == nil)
        print("PASS: school evidence summary survives reopening and is scoped to its account")
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw OiServiceError.unavailable }
                if count == 0 { break }
                data.append(buffer, count: count)
            }
        }
        return data
    }

    static func checkCardRequests(api: OiServiceAPI) async throws {
        let id = UUID()
        let fixture: [String: String] = [
            "id": id.uuidString, "story_title": "우리가 남긴 이야기", "requester_name": "새싹",
            "requester_school_name": "POSTECH", "created_at": "2026-11-04T09:00:00.123456+00:00", "status": "pending"
        ]
        OiURLProtocol.handler = { request in
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer card-request-test")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String]
            switch request.url?.path {
            case "/rest/v1/rpc/oi_card_requests":
                precondition(body == [:])
                return (200, try JSONSerialization.data(withJSONObject: [fixture]))
            case "/rest/v1/rpc/oi_resolve_card_request":
                precondition(body == ["p_request_id": id.uuidString, "p_decision": "accept"])
                return (200, try JSONSerialization.data(withJSONObject: fixture.merging(["status": "accepted"]) { _, updated in updated }))
            default:
                preconditionFailure("Unexpected card request endpoint")
            }
        }
        let inbox = try await api.cardRequests(token: "card-request-test")
        precondition(inbox.count == 1 && inbox.first?.id == id && inbox.first?.status == .pending)
        precondition(inbox.first?.storyTitle == fixture["story_title"] && inbox.first?.requesterSchoolName == "POSTECH")
        let receipt = try await api.resolveCardRequest(id, accept: true, token: "card-request-test")
        precondition(receipt.status == .accepted)
        OiURLProtocol.handler = { _ in (200, try JSONSerialization.data(withJSONObject: fixture)) }
        do {
            _ = try await api.resolveCardRequest(id, accept: false, token: "card-request-test")
            preconditionFailure("An uncommitted decision must not be shown as saved")
        } catch OiServiceError.unavailable {}
        OiURLProtocol.handler = { _ in (401, Data()) }
        do {
            _ = try await api.cardRequests(token: "card-request-test")
            preconditionFailure("An unauthenticated read must not be shown as an empty inbox")
        } catch OiServiceError.signInRequired {}
        print("PASS: card request auth, timestamp, RPC payload and verified decision receipt")
    }

    static func checkCardGestures() {
        var session = OiCardGestureState()
        var p = OiCardPlacement()
        var angle: OiCardOrientation? = .init()
        func input(_ points: [Int: CGPoint]) {
            session.update(points: points, bounds: CGSize(width: 200, height: 300), placement: &p, orientation: &angle)
        }
        input([0: CGPoint(x: 50, y: 100)])
        input([0: CGPoint(x: 70, y: 130)])
        precondition(abs(p.x - 0.6) < 0.0001 && abs(p.y - 0.6) < 0.0001)
        input([0: CGPoint(x: 70, y: 130), 1: CGPoint(x: 130, y: 130)])
        let position = p
        // Symmetric pinch changes size only, around the character's fixed center.
        input([0: CGPoint(x: 40, y: 130), 1: CGPoint(x: 160, y: 130)])
        precondition(p.x == position.x && p.y == position.y && p.scale == 2)
        precondition(angle == OiCardOrientation())
        // Translating both fingers rotates the model without moving the card layer.
        input([0: CGPoint(x: 60, y: 140), 1: CGPoint(x: 180, y: 140)])
        precondition(p.x == position.x && p.y == position.y && p.scale == 2)
        precondition(abs((angle?.yaw ?? 0) + 0.2) < 0.0001)
        let rotated = angle
        // A remaining finger after pinch/orbit must NOT become a move gesture.
        input([0: CGPoint(x: 60, y: 140)])
        input([0: CGPoint(x: 90, y: 200)])
        precondition(p.x == position.x && p.y == position.y && angle == rotated)
        input([:])
        input([2: CGPoint(x: 10, y: 10)])
        input([2: CGPoint(x: 30, y: 10)])
        precondition(abs(p.x - position.x - 0.1) < 0.0001)
        // Third finger and a replaced finger rebase without a jump.
        input([2: CGPoint(x: 30, y: 10), 3: CGPoint(x: 80, y: 10), 4: CGPoint(x: 90, y: 90)])
        let beforeReplacement = p
        input([3: CGPoint(x: 80, y: 10), 4: CGPoint(x: 90, y: 90)])
        precondition(p == beforeReplacement && angle == rotated)
        input([:])
        angle = nil
        input([0: CGPoint(x: 20, y: 50), 1: CGPoint(x: 80, y: 50)])
        let background = p
        input([0: CGPoint(x: 40, y: 80), 1: CGPoint(x: 100, y: 80)])
        precondition(abs(p.x - background.x - 0.1) < 0.0001 && abs(p.y - background.y - 0.1) < 0.0001)
        print("PASS: card one-finger move, pinch scale, two-finger orbit, 2→1 lock, touch replacement and background pan")
    }

    @MainActor static func main() async throws {
        checkCardGestures()
        try checkFieldTrial()
        try await checkSchoolReviewRecovery()
        for key in ["", "sb_secret_test", "$(UNSET)", "sb_publishable_bad\nheader"] {
            do { _ = try OiServiceAPI(key: key); preconditionFailure("Invalid key accepted") }
            catch OiServiceError.configuration {}
        }
        let privilegedPayload = Data("{\"role\":\"service_role\",\"ref\":\"kfzfzarslqdqmrazohej\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        do { _ = try OiServiceAPI(key: "ey.\(privilegedPayload).test"); preconditionFailure("Privileged key accepted") }
        catch OiServiceError.configuration {}

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); OiURLProtocol.handler = nil }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        try await checkCardRequests(api: api)
        OiURLProtocol.handler = { request in
            precondition(request.url?.scheme == "https" && request.url?.host == OiServiceAPI.projectHost)
            precondition(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_testing")
            let count = request.url?.query?.contains("offset=200") == true ? 2 : 200
            let start = count == 2 ? 199 : 0
            let rows = (start..<(start+count)).map { index in
                ["id": String(format: "b1000000-0000-4000-8000-%012d",index), "nickname":"Test", "farmer_asset":"OiFarmer"]
            }
            return (200, try JSONSerialization.data(withJSONObject: rows))
        }
        let profiles = try await api.rows("oi_profiles", as: OiProfile.self)
        precondition(profiles.count == 201 && Set(profiles.map(\.id)).count == 201)
        precondition(profiles.allSatisfy { $0.publicName == nil && $0.department == nil && $0.admissionYear == nil }, "Pre-migration profile responses remain readable")

        let publicID = UUID()
        func publicFixture(status: String, id: UUID) throws -> Data {
            try JSONSerialization.data(withJSONObject: [[
                "id": id.uuidString, "user_id": UUID().uuidString, "grant_id": UUID().uuidString,
                "region_id": "pond", "title": "Test", "body": "Test story", "theme": "Test", "emotion": "Test",
                "cucumber_name": "Test", "cucumber_asset": "OiCats", "card_asset": "MYBasicCard",
                "latitude": 36.012, "longitude": 129.32, "status": status, "revision": 1,
                "created_at": "2026-10-28T00:00:00Z"
            ]])
        }
        let publicData = try publicFixture(status: "published", id: publicID)
        OiURLProtocol.handler = { request in
            precondition(request.url?.path == "/rest/v1/oi_stories")
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            let query = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems ?? []
            precondition(query.contains { $0.name == "id" && $0.value == "eq.\(publicID.uuidString)" })
            precondition(query.contains { $0.name == "status" && $0.value == "eq.published" })
            return (200, publicData)
        }
        let publicStory = try await api.publishedStory(publicID)
        precondition(publicStory.id == publicID)
        for invalid in [Data("[]".utf8), try publicFixture(status: "hidden", id: publicID), try publicFixture(status: "published", id: UUID())] {
            OiURLProtocol.handler = { _ in (200, invalid) }
            do { _ = try await api.publishedStory(publicID); preconditionFailure("Non-public or mismatched AR story accepted") }
            catch OiServiceError.unavailable {}
        }
        OiURLProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil, "Nearby query must not use owner privileges")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            precondition(query.contains { $0.name == "status" && $0.value == "eq.published" })
            precondition(query.contains { $0.name == "order" && $0.value == "id.asc" })
            return (200, publicData)
        }
        let nearby = try await api.publishedStories()
        precondition(nearby.map(\.id) == [publicID])
        let hiddenData = try publicFixture(status: "hidden", id: publicID)
        OiURLProtocol.handler = { _ in (200, hiddenData) }
        let hiddenNearby = try await api.publishedStories()
        precondition(hiddenNearby.isEmpty)
        OiURLProtocol.handler = { _ in (503, Data()) }
        do { _ = try await api.publishedStories(); preconditionFailure("Network failure must not return cached nearby objects") }
        catch OiServiceError.unavailable { }
        print("PASS: AR public-role lookup, stable story identity, hidden/deleted/mismatched story rejection")

        OiURLProtocol.handler = { request in
            precondition(request.url?.path == "/rest/v1/rpc/oi_mutate")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-user-token")
            let data = try requestBody(request)
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw OiServiceError.unavailable }
            precondition(body["p_action"] as? String == "collect")
            return (200, Data("{\"id\":\"b1000000-0000-4000-8000-000000000020\"}".utf8))
        }
        struct Mutation: Decodable { let id: UUID }
        let mutation = try await api.mutate("collect", payload: ["id":"b1000000-0000-4000-8000-000000000020"], token: "test-user-token", as: Mutation.self)
        precondition(mutation.id.uuidString.lowercased().hasSuffix("20"))

        OiURLProtocol.handler = { request in
            precondition(request.url?.query == "grant_type=pkce")
            return (200, Data("{\"access_token\":\"test-access\",\"refresh_token\":\"test-refresh\",\"expires_in\":3600,\"user\":{\"id\":\"b1000000-0000-4000-8000-000000000001\"}}".utf8))
        }
        let authenticated = try await api.session(grant: "pkce", payload: ["auth_code":"test-code","code_verifier":"test-verifier"])
        precondition(!authenticated.needsRefresh && authenticated.user.email == nil)

        OiURLProtocol.handler = { _ in (403, Data()) }
        do { _ = try await api.request("rest/v1/oi_stories"); preconditionFailure("Forbidden accepted") }
        catch OiServiceError.server {}

        var draft = OiStoryDraft()
        precondition(!draft.valid)
        draft.grantId = UUID(); draft.title = "Title"; draft.body = "Body"
        draft.theme = "감사"; draft.emotion = "기쁨"; draft.cucumberName = "Test"
        draft.latitude = 36.01261057021347; draft.longitude = 129.3197268697784
        precondition(draft.valid)
        var temporaryDraft = draft
        temporaryDraft.grantId = nil
        precondition(temporaryDraft.valid)
        let temporaryPayload = try temporaryDraft.payload()
        precondition(temporaryPayload["grant_id"] is NSNull)
        let grant = OiWritingGrant(id: draft.grantId!, storyLimit: 1, revokedAt: nil)
        precondition(OiWritingAccess.canWrite(grantID: nil, grants: [], unapprovedDraftsEnabled: true))
        precondition(!OiWritingAccess.canWrite(grantID: nil, grants: [], unapprovedDraftsEnabled: false))
        precondition(OiWritingAccess.canWrite(grantID: grant.id, grants: [grant], unapprovedDraftsEnabled: false))
        precondition(!OiWritingAccess.canWrite(grantID: grant.id, grants: [], unapprovedDraftsEnabled: true))
        let revoked = OiWritingGrant(id: grant.id, storyLimit: 1, revokedAt: "2026-11-04")
        precondition(!OiWritingAccess.canWrite(grantID: grant.id, grants: [revoked], unapprovedDraftsEnabled: true))
        let capabilityDecoder = JSONDecoder()
        capabilityDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let oldCapabilities = try capabilityDecoder.decode(OiCapabilities.self, from: Data("{\"operator\":false,\"coins_enabled\":false}".utf8))
        precondition(oldCapabilities.unapprovedDraftsEnabled != true)
        precondition(OiCreationStep.allCases.allSatisfy { $0.canContinue(draft: draft) })
        precondition(OiCreationStep.consent.previous == nil && OiCreationStep.story.previous == .consent && OiCreationStep.card.next == nil)
        var invalid = draft; invalid.title = String(repeating: "가", count: 101)
        precondition(!OiCreationStep.story.canContinue(draft: invalid))
        invalid = draft; invalid.emotion = "   "
        precondition(!OiCreationStep.story.canContinue(draft: invalid))
        invalid = draft; invalid.latitude = .nan
        precondition(!OiCreationStep.location.canContinue(draft: invalid))
        invalid = draft; invalid.longitude = 181
        precondition(!OiCreationStep.location.canContinue(draft: invalid))
        invalid = draft; invalid.cucumberName = String(repeating: "가", count: 51)
        precondition(OiCreationStep.cucumber.canContinue(draft: invalid))
        precondition(!OiCreationStep.card.canContinue(draft: invalid))
        invalid.cucumberName = ""
        precondition(OiCreationStep.cucumber.canContinue(draft: invalid), "Name entry now belongs to the card step")
        precondition(!OiCreationStep.card.canContinue(draft: invalid), "A missing name still blocks review")
        for status in ["pending", "published", "hidden", "deleted"] {
            precondition(!OiCreationAccess.canEdit(status: status, submitted: false))
        }
        precondition(OiCreationAccess.canEdit(status: "draft", submitted: true))
        precondition(!OiCreationAccess.canEdit(status: nil, submitted: true))
        let localA = UUID(), localB = UUID(), removedPhoto = UUID()
        let oldPath = "owner/story/remote-only.jpg"
        let localPath = "owner/story/\(localA.uuidString.lowercased()).jpg"
        let removedPath = "owner/story/\(removedPhoto.uuidString.lowercased()).jpg"
        let ordered = OiEditingPhoto.ordered(local: [localA, localB], remote: [oldPath, localPath, removedPath], removed: [removedPath])
        precondition(ordered == [.uploaded(oldPath), .local(localA), .local(localB)])
        let lateReceipt = OiEditingPhoto.ordered(local: [localA, removedPhoto],
            remote: [oldPath, localPath, removedPath], removed: [], removedPhotoIDs: [removedPhoto])
        precondition(lateReceipt == [.uploaded(oldPath), .local(localA)],
                     "A locally deleted photo must not return after a lost upload receipt or a late refresh")
        let currentServerDraft = OiLiveStory(id: draft.id, userId: UUID(), grantId: draft.grantId!,
            regionId: draft.regionId, title: draft.title, body: draft.body, theme: draft.theme, emotion: draft.emotion,
            cucumberName: draft.cucumberName, cucumberAsset: draft.cucumberAsset, cardAsset: draft.cardAsset,
            latitude: draft.latitude!, longitude: draft.longitude!, status: "draft", revision: 4, createdAt: "")
        precondition(OiCreationAccess.canRebase(draft, to: currentServerDraft),
                     "A revision bump with identical content can be reconciled without overwriting the local draft")
        var localEdit = draft
        localEdit.body += " with a new paragraph"
        precondition(!OiCreationAccess.canRebase(localEdit, to: currentServerDraft),
                     "A distinct local edit must never be silently rebased over a changed server draft")
        print("PASS: creation validation, server review lock, and stable deduplicated photo ordering")
        let payload = try draft.payload()
        precondition(payload["revision"] as? Int == 0 && payload["cucumber_asset"] as? String == "OiCats")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { preconditionFailure("Draft test cleanup failed") } }
        let vault = OiDraftVault(directory: directory)
        let owner = UUID(), other = UUID(), photoID = UUID()
        var record = OiLocalDraft(draft: draft, photos: [photoID], version: 2)
        let legacyJSON = try JSONEncoder().encode(record)
        let legacy = try JSONDecoder().decode(OiLocalDraft.self, from: legacyJSON)
        precondition(legacy.creationStep == nil && legacy.customization == nil &&
                     legacy.removedMediaPaths == nil && legacy.removedPhotoIDs == nil &&
                     legacy.agreedConsentClauseIDs == nil, "Legacy drafts must not imply consent")
        record.agreedConsentClauseIDs = ["storyWriting"]
        let consentRoundTrip = try JSONDecoder().decode(OiLocalDraft.self, from: JSONEncoder().encode(record))
        precondition(consentRoundTrip.agreedConsentClauseIDs == ["storyWriting"])
        record.creationStep = OiCreationStep.card.rawValue
        record.customization = OiDraftCustomization(fill: .gradient, firstColor: 0xABCDEF, secondColor: 0x123456,
                                                   showsCharacter: false, garmentColors: ["모자":0x445566])
        // Old customization records have no wardrobe key and must still recover.
        let oldCustomization = try JSONEncoder().encode(record.customization!)
        let oldRecovered = try JSONDecoder().decode(OiDraftCustomization.self, from: oldCustomization)
        precondition(oldRecovered.wardrobe == nil && oldRecovered.card == nil)
        let future = try JSONDecoder().decode(OiWardrobeLook.self, from: Data(#"{"top":"future-garment","bottom":"retired-pants","topColor":4294967295}"#.utf8))
        precondition(future.top == .tshirt && future.bottom == .long && future.topColor == 0xFFFFFF)
        precondition(future.fabrics.isEmpty, "Legacy looks have no fabric override")
        let futureFabric = try JSONDecoder().decode(OiWardrobeLook.self, from: Data(#"{"fabrics":{"bottom-long":"03-deep-indigo","top-tshirt":"future-fabric","unknown-item":"06-ecru"}}"#.utf8))
        precondition(futureFabric.fabrics == ["bottom-long": .deepIndigo], "Unknown fabric/item IDs must not discard a saved look")
        var look = OiWardrobeLook()
        look.top = .hoodie; look.bottom = .shorts
        look.topColor = 0xC5DBEC; look.bottomColor = 0xD7CBB8; look.shoeColor = 0xF2EBDD
        look.topColor = 0x17A3EF
        look.fabrics = ["top-hoodie": .ecru, "bottom-long": .deepIndigo, "bottom-shorts": .lightBlue]
        precondition(OiPhotoSlot.bottom.fabric(in: look) == .lightBlue)
        var longLook = look; longLook.bottom = .long
        precondition(OiPhotoSlot.bottom.fabric(in: longLook) == .deepIndigo)
        precondition(future.artwork.designs.isEmpty, "Existing looks without artwork still decode")
        let source = String(repeating: "a", count: 64)
        var front = OiPhotoLayer(source: source)
        front.placement = OiPhotoPlacement(x: 0.3, y: 0.6, width: 0.7, rotation: 27)
        var back = OiPhotoLayer(source: source); back.side = .back
        var front2 = front; front2.id = UUID().uuidString
        var back2 = back; back2.id = UUID().uuidString
        let fullFaces = [front, front2, back, back2]
        precondition(OiPhotoEditingLimit.remaining(on: .front, in: fullFaces) == 0)
        precondition(OiPhotoEditingLimit.remaining(on: .back, in: fullFaces) == 0)
        precondition(OiPhotoEditingLimit.remaining(on: .back, in: [front, front2]) == 2)
        var legacyThird = front; legacyThird.id = UUID().uuidString
        let legacyDesign = OiPhotoDesign(layers: [front, front2, legacyThird])
        let recoveredDesign = try JSONDecoder().decode(OiPhotoDesign.self, from: JSONEncoder().encode(legacyDesign))
        precondition(recoveredDesign == legacyDesign && recoveredDesign.isValid, "Existing photos must survive the new editing limit")
        precondition(OiPhotoEditingLimit.remaining(on: .front, in: recoveredDesign.layers) == 0)
        let design = OiPhotoDesign(layers: [front, back])
        try look.artwork.set(design, sources: [source: Data([10,20,30])], for: "top-hoodie")
        try look.artwork.set(OiPhotoDesign(layers: [back]), for: "bottom-shorts")
        precondition(look.artwork.sources.count == 1, "Source bytes deduplicate across garments and layers")
        var edited = look.artwork
        try edited.set(nil, for: "top-hoodie")
        precondition(edited.sources.count == 1 && look.artwork.designs.count == 2, "Cancel/edit copy cannot alter committed design")
        try edited.set(nil, for: "bottom-shorts")
        precondition(edited.sources.isEmpty, "Remove the source only after its last garment reference")
        let beforeFailure = look.artwork
        do {
            try look.artwork.set(OiPhotoDesign(layers: Array(repeating: front, count: 9)), for: "top-hoodie")
            preconditionFailure("Over-limit and duplicate layer IDs accepted")
        } catch OiPhotoDataError.limit { }
        precondition(look.artwork == beforeFailure, "Failed updates must be atomic")
        do {
            try look.artwork.set(design, sources: [source: Data(repeating: 1, count: OiWardrobeArtwork.maximumSourceBytes + 1)], for: "top-hoodie")
            preconditionFailure("Oversized source accepted")
        } catch OiPhotoDataError.limit { }
        var invalidLayer = front; invalidLayer.placement.width = .nan
        precondition(!OiPhotoDesign(layers: [invalidLayer]).isValid)
        invalidLayer = front; invalidLayer.source = "../../private.jpg"
        precondition(!OiPhotoDesign(layers: [invalidLayer]).isValid)
        do {
            try look.artwork.set(design, for: "top-unknown")
            preconditionFailure("Unsupported garment accepted")
        } catch OiPhotoDataError.limit { }
        try look.artwork.set(design, for: "top-postech")
        print("PASS: photo layer bounds, invalid transforms, atomic rejection, deduplicated source lifecycle")
        precondition(future.costume == nil)
        let unsupportedCostume = try JSONDecoder().decode(OiWardrobeLook.self, from: Data(#"{"costume":"retired-dinosaur-bear"}"#.utf8))
        precondition(unsupportedCostume.costume == nil)
        for costume in OiWardrobeLook.Costume.allCases {
            var dressed = look; dressed.costume = costume
            precondition(dressed.modelName == costume.modelName && dressed.title == costume.title)
            precondition(OiPhotoSlot.top.supports(dressed) && !OiPhotoSlot.bottom.supports(dressed))
            precondition(OiPhotoSlot.top.preservesOriginalMaterial(in: dressed))
            let itemID = OiPhotoSlot.top.itemID(in: dressed)
            precondition(itemID == "costume-" + costume.rawValue)
            try dressed.artwork.set(design, for: itemID)
            precondition(dressed.artwork.sources.count == 1, "Sets share existing source bytes")
            let restored = try JSONDecoder().decode(OiWardrobeLook.self, from: JSONEncoder().encode(dressed))
            precondition(restored == dressed)
            var individual = restored; individual.costume = nil
            try individual.artwork.set(nil, for: itemID)
            precondition(individual == look, "Returning to individual items preserves colors, denim and photos")
        }
        look.costume = .dinosaur
        print("PASS: complete costume persistence, unsupported ID fallback and individual-look restoration")
        record.customization?.wardrobe = look
        var card = OiCardDesign()
        card.borderFill = .gradient; card.borderFirst = 0xF9F2E5; card.borderSecond = 0xE4E7EB
        card.caption = "함께한 캠퍼스"; card.anonymous = true; card.pattern = 3
        card.characterPlacement = OiCardPlacement(x: 0.31, y: 0.68, scale: 2.4)
        card.backgroundPlacement = OiCardPlacement(x: 0.44, y: 0.62, scale: 1.8)
        // New optional pose must decode old card drafts and survive account-vault reopening.
        let legacyCardBytes = try JSONEncoder().encode(card)
        let legacyCard = try JSONDecoder().decode(OiCardDesign.self, from: legacyCardBytes)
        precondition(legacyCard.characterOrientation == nil)
        card.characterOrientation = OiCardOrientation(yaw: .pi / 2, pitch: 0.3)
        let invalidAngle = OiCardOrientation(yaw: .infinity, pitch: .nan).normalized
        precondition(invalidAngle == OiCardOrientation())
        let wrappedAngle = OiCardOrientation(yaw: 5 * .pi, pitch: 8).normalized
        precondition(abs(wrappedAngle.yaw) <= .pi && wrappedAngle.pitch == .pi / 3)
        let movedAngle = OiCardOrientation().rotated(horizontal: 50, vertical: 30)
        precondition(movedAngle == OiCardOrientation(yaw: -0.5, pitch: 0.3))
        precondition(movedAngle.cacheIdentity != OiCardOrientation().cacheIdentity)
        precondition(OiCardOrientation(yaw: 2 * .pi).cacheIdentity == OiCardOrientation().cacheIdentity)
        card.backgroundPhoto = Data([1,2,3]); card.portraitPNG = Data([4,5,6]); card.portraitKey = "test-look"
        record.customization?.card = card
        let bounded = OiCardPlacement(x: .infinity, y: -8, scale: 100).normalized
        precondition(bounded.x == 0.5 && bounded.y == -0.25 && bounded.scale == 4)
        precondition(OiCardPlacement(x: 0.2, y: 0.8, scale: 1.7).normalized == OiCardPlacement(x: 0.2, y: 0.8, scale: 1.7))
        record.removedMediaPaths = [oldPath]
        record.removedPhotoIDs = [removedPhoto]
        try await vault.saveAttachment(Data([1,2,3]), owner: owner, id: photoID)
        try await vault.save(record, owner: owner)
        record.version = 1; record.draft.title = "Stale edit"
        try await vault.save(record, owner: owner)
        let reopened = OiDraftVault(directory: directory)
        let recovered = try await reopened.load(owner: owner, id: draft.id)
        precondition(recovered?.draft.title == "Title" && recovered?.photos == [photoID])
        precondition(recovered?.creationStep == "card" && recovered?.customization?.fill == .gradient)
        precondition(recovered?.customization?.firstColor == 0xABCDEF && recovered?.customization?.garmentColors["모자"] == 0x445566)
        precondition(recovered?.customization?.showsCharacter == false && recovered?.removedMediaPaths == [oldPath])
        precondition(recovered?.removedPhotoIDs == [removedPhoto], "Removal intent must survive reopening after a lost receipt")
        precondition(recovered?.customization?.card == card, "Card framing, portrait, background, caption and privacy choice must survive vault reopening")
        precondition(recovered?.customization?.card?.characterOrientation == card.characterOrientation)
        print("PASS: card framing, 3D orientation and artwork survive draft recovery; legacy cards and public payload unchanged")
        precondition(recovered?.customization?.wardrobe == look, "Garments and all three colors must survive reopening the account draft")
        precondition(recovered?.customization?.wardrobe?.artwork == look.artwork)
        precondition(recovered?.customization?.wardrobe?.fabrics == look.fabrics)
        precondition(recovered?.customization?.wardrobe?.topColor == 0x17A3EF)
        print("PASS: per-item denim and arbitrary RGB survive draft reopening alongside photos")
        print("PASS: legacy wardrobe migration, garment/color/photo layers and compressed source relaunch recovery")
        precondition(payload["customization"] == nil && payload["creationStep"] == nil, "Local scaffold must not alter shared API")
        let photoData = try await reopened.attachment(owner: owner, id: photoID)
        precondition(photoData == Data([1,2,3]))
        let unrelated = try await reopened.list(owner: other)
        precondition(unrelated.isEmpty)
        let operation = OiEvidenceOperation(requestID: UUID(), uploadID: UUID(), contentType: "image/png", fileExtension: "png", phase: "failed", failure: "offline")
        try await vault.saveEvidence(operation, owner: owner)
        let resumedOperation = try await reopened.evidence(owner: owner)
        precondition(resumedOperation == operation && resumedOperation?.objectPath(owner: owner) == operation.objectPath(owner: owner))
        try await reopened.discard(owner: owner, id: draft.id)
        let discarded = try await vault.load(owner: owner, id: draft.id)
        precondition(discarded == nil)
        print("PASS: configuration safety, paginated deduplication, owner RPC, PKCE exchange decoding, expiry, HTTP errors, draft validation")
        print("PASS: account-scoped draft/photo relaunch recovery, stale-write protection, stable evidence retry identity, explicit draft deletion")
    }
}
