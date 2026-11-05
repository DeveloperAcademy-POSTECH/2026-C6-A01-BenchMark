//
//  OiAppleExchangeChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import Foundation

private final class AppleExchangeProtocol: URLProtocol {
    static var status = 200
    static var exchanges = 0
    static let rawNonce = "test-only-raw-nonce"
    static let identityToken = "test-only-apple-identity-token"
    static let accessToken = "test-only-access-token"
    static let refreshToken = "test-only-refresh-token"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try required(request.url)
            precondition(url.host == OiServiceAPI.projectHost)
            precondition(url.path == "/auth/v1/token")
            precondition(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "grant_type" })?.value == "id_token")
            precondition(request.httpMethod == "POST")
            let payload = try JSONSerialization.jsonObject(with: requestBody()) as? [String: String]
            precondition(payload == ["provider": "apple", "id_token": Self.identityToken, "nonce": Self.rawNonce])
            precondition(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test-only")
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            Self.exchanges += 1
            let response = try required(HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil))
            let body: [String: Any]
            if Self.status == 200 {
                body = ["access_token": Self.accessToken, "refresh_token": Self.refreshToken,
                        "expires_in": 3600, "expires_at": 0,
                        "user": ["id": "b1000000-0000-4000-8000-000000000001"]]
            } else {
                // A provider may return unsafe context; the client must never display this body.
                body = ["message": "Rejected " + Self.identityToken + " " + Self.rawNonce]
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}

    private func required<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw OiServiceError.invalidInput }
        return value
    }

    private func requestBody() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try required(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return data }
            guard count > 0 else { throw OiServiceError.invalidInput }
            data.append(buffer, count: count)
        }
    }
}

@main
private struct OiAppleExchangeChecks {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppleExchangeProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let api = try OiServiceAPI(key: "sb_publishable_test-only", session: transport)
        let payload = ["provider": "apple", "id_token": AppleExchangeProtocol.identityToken,
                       "nonce": AppleExchangeProtocol.rawNonce]
        let before = Date().timeIntervalSince1970
        let session = try await api.session(grant: "id_token", payload: payload)
        let after = Date().timeIntervalSince1970
        precondition(session.accessToken == AppleExchangeProtocol.accessToken)
        precondition(session.refreshToken == AppleExchangeProtocol.refreshToken)
        precondition(session.user.id.uuidString.lowercased() == "b1000000-0000-4000-8000-000000000001")
        precondition(session.expiresAt.map { $0 >= before + 3600 && $0 <= after + 3600 } == true)
        precondition(!session.needsRefresh)
        print("PASS: Apple id_token exchange preserves provider and raw nonce; session identity and expiry are decoded")

        for status in [400,401,429,503] {
            AppleExchangeProtocol.status = status
            do {
                _ = try await api.session(grant: "id_token", payload: payload)
                preconditionFailure("Failed Apple exchange unexpectedly succeeded")
            } catch {
                switch (status, error) {
                case (400, OiServiceError.authenticationFailed), (401, OiServiceError.signInRequired),
                     (429, OiServiceError.server), (503, OiServiceError.unavailable): break
                default: preconditionFailure("Apple exchange returned an incorrect error category")
                }
                let message = error.localizedDescription
                for sensitive in [AppleExchangeProtocol.identityToken, AppleExchangeProtocol.rawNonce,
                                  AppleExchangeProtocol.accessToken, AppleExchangeProtocol.refreshToken] {
                    precondition(!message.contains(sensitive))
                }
            }
        }
        precondition(AppleExchangeProtocol.exchanges == 5)
        print("PASS: Apple token rejection, expired authorization, rate limit, and unavailable service do not expose tokens or nonce")
    }
}
