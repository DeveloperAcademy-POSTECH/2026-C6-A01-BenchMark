import Foundation

final class CampusStub: URLProtocol {
    nonisolated(unsafe) static var handler: (URLRequest) throws -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status,data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@main struct CampusSharedChecks {
    @MainActor static func main() async throws {
        for input in ["", "http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com?token=secret", "https://example.com#fragment"] {
            precondition(CampusSharedAPI.approvedOrigin(input) == nil)
        }
        precondition(CampusSharedAPI.approvedOrigin("https://example.com/") != nil)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CampusStub.self]
        let api = CampusSharedAPI(origin: URL(string:"https://example.com"), session: URLSession(configuration: config))
        let id = UUID(), otherID = UUID()
        func item(_ id: UUID, _ changes: [String: Any] = [:]) -> [String: Any] {
            ["id":id.uuidString, "storyID":id.uuidString, "campusID":"postech", "model":"helmet-oi", "latitude":36.01, "longitude":129.32, "heightMeters":1.0, "headingDegrees":20.0, "displayName":"가상 농부", "title":"검증", "story":"검증 본문", "status":"published", "revision":1, "updatedAt":"2026-01-01T00:00:00.000Z"].merging(changes) { _, new in new }
        }
        func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
        CampusStub.handler = { req in
            precondition(req.value(forHTTPHeaderField:"Authorization") == nil)
            let second = req.url!.query != nil
            return (200, try data(["items":[item(second ? otherID : id)], "nextCursor":second ? NSNull() : id.uuidString as Any]))
        }
        let all = try await api.list(); precondition(all.map(\.id) == [id,otherID])
        CampusStub.handler = { _ in (200, try data(item(id))) }
        let story = try await api.story(id); precondition(story.placement.id == id && story.placement.storyID == story.storyID)
        for change in [["status":"pending"], ["model":"https://bad.invalid/model"], ["latitude":1000.0], ["storyID":otherID.uuidString]] as [[String:Any]] {
            CampusStub.handler = { _ in (200, try data(["items":[item(id,change)],"nextCursor":NSNull()])) }
            do { _ = try await api.list(); preconditionFailure("Invalid response accepted") } catch { }
        }
        CampusStub.handler = { _ in (200, try data(["items":[item(id)],"nextCursor":id.uuidString])) }
        do { _ = try await api.list(); preconditionFailure("Repeated cursor accepted") } catch { }
        CampusStub.handler = { req in
            precondition(req.value(forHTTPHeaderField:"Authorization") == "Bearer test-token")
            return (401, try data(["error":"expired"]))
        }
        do { _ = try await api.story(id,token:"test-token"); preconditionFailure("Auth error swallowed") }
        catch CampusSharedError.unauthorized { }
        CampusStub.handler = { _ in (404, try data(["error":"hidden"])) }
        do { _ = try await api.story(id); preconditionFailure("Hidden story accepted") }
        catch CampusSharedError.unavailable { }
        CampusStub.handler = { req in
            precondition(req.httpMethod == "POST" && req.value(forHTTPHeaderField:"Authorization") == "Bearer test-token")
            return (201, try data(["id":id.uuidString]))
        }
        try await api.save(CampusSharedDraft(id:id,latitude:36.01,longitude:129.32,heightMeters:1,headingDegrees:20,displayName:"검증",title:"검증",story:"검증",revision:nil),token:"test-token")
        print("PASS: HTTPS configuration, pagination, public validation, auth errors and shared map/AR identity")
    }
}
