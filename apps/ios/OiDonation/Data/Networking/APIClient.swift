import Foundation

/// Transport only. Endpoints and DTOs are added after the backend contract is approved.
struct APIClient {
    let session: URLSession
    let approvedHost: String

    init(session: URLSession = .shared, approvedHost: String) {
        self.session = session
        self.approvedHost = approvedHost
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await response(request)
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        return data
    }

    /// Exposes status/body to endpoint-specific error decoders after host validation.
    func response(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https",
              url.host?.lowercased() == approvedHost.lowercased(),
              url.user == nil, url.password == nil else { throw APIError.untrustedEndpoint }
        let (data, response) = try await session.data(for: request, delegate: ApprovedHostRedirectDelegate(host: approvedHost))
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        // Reject unexpected redirects before exposing data to repositories.
        guard http.url?.host?.lowercased() == approvedHost.lowercased(),
              http.url?.scheme == "https" else { throw APIError.untrustedEndpoint }
        return (data, http)
    }
}

enum APIError: Error {
    case untrustedEndpoint, invalidResponse, httpStatus(Int)
}

private final class ApprovedHostRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https",
              url.host?.lowercased() == host.lowercased(),
              url.user == nil, url.password == nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
