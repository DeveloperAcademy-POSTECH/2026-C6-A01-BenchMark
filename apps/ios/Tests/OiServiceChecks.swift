// Created by 이돈혁

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
    @MainActor static func main() async throws {
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
        print("PASS: AR public-role lookup, stable story identity, hidden/deleted/mismatched story rejection")

        OiURLProtocol.handler = { request in
            precondition(request.url?.path == "/rest/v1/rpc/oi_mutate")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-user-token")
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
        let payload = try draft.payload()
        precondition(payload["revision"] as? Int == 0 && payload["cucumber_asset"] as? String == "OiCats")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { preconditionFailure("Draft test cleanup failed") } }
        let vault = OiDraftVault(directory: directory)
        let owner = UUID(), other = UUID(), photoID = UUID()
        var record = OiLocalDraft(draft: draft, photos: [photoID], version: 2)
        try await vault.saveAttachment(Data([1,2,3]), owner: owner, id: photoID)
        try await vault.save(record, owner: owner)
        record.version = 1; record.draft.title = "Stale edit"
        try await vault.save(record, owner: owner)
        let reopened = OiDraftVault(directory: directory)
        let recovered = try await reopened.load(owner: owner, id: draft.id)
        precondition(recovered?.draft.title == "Title" && recovered?.photos == [photoID])
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
