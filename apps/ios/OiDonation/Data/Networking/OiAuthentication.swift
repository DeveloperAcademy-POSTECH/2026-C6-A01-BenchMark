// Created by 이돈혁

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct OiSessionVault: OiSessionStorage {
    private let service = "com.Spero.OiDonation.supabase.session"

    func read() throws -> OiSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw OiServiceError.secureStorage(status) }
        return try JSONDecoder().decode(OiSession.self, from: data)
    }

    func write(_ session: OiSession?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw OiServiceError.secureStorage(status) }
            return
        }
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var values = query
            values[kSecValueData as String] = data
            values[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(values as CFDictionary, nil)
            guard added == errSecSuccess else { throw OiServiceError.secureStorage(added) }
        } else if status != errSecSuccess { throw OiServiceError.secureStorage(status) }
    }
}

@MainActor
final class OiGoogleAuthentication: NSObject, OiAuthenticating, ASWebAuthenticationPresentationContextProviding {
    static let callback = OiServiceAPI.authenticationCallback
    private var webSession: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    private var attemptID: UUID?
    private var continuation: CheckedContinuation<URL, Error>?

    func signIn(api: OiServiceAPI) async throws -> OiSession {
        try Task.checkCancellation()
        guard attemptID == nil else { throw OiServiceError.unavailable }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw OiServiceError.unavailable }
        let verifier = Data(random).base64URLEncoded
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow) else { throw OiServiceError.unavailable }
        let attempt = UUID()
        attemptID = attempt
        anchor = window
        defer {
            if attemptID == attempt {
                webSession = nil; anchor = nil; attemptID = nil; continuation = nil
            }
        }
        guard var components = URLComponents(string: "https://\(OiServiceAPI.projectHost)/auth/v1/authorize") else {
            throw OiServiceError.unavailable
        }
        components.queryItems = [URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Self.callback), URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"), URLQueryItem(name: "prompt", value: "select_account")]
        guard let url = components.url else { throw OiServiceError.invalidCallback }
        let callback: URL = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let authentication = ASWebAuthenticationSession(url: url, callbackURLScheme: "kr.ac.postech.benchmark") { [weak self] callback, error in
                    Task { @MainActor in
                        if let failure = error as? ASWebAuthenticationSessionError, failure.code == .canceledLogin {
                            self?.complete(attempt, result: .failure(CancellationError()))
                        } else if let error {
                            self?.complete(attempt, result: .failure(error))
                        } else if let callback {
                            self?.complete(attempt, result: .success(callback))
                        } else {
                            self?.complete(attempt, result: .failure(OiServiceError.invalidCallback))
                        }
                    }
                }
                authentication.presentationContextProvider = self
                webSession = authentication
                if !authentication.start() { complete(attempt, result: .failure(OiServiceError.unavailable)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.attemptID == attempt else { return }
                let session = self.webSession
                self.complete(attempt, result: .failure(CancellationError()))
                session?.cancel()
            }
        }
        try Task.checkCancellation()
        guard callback.scheme == "kr.ac.postech.benchmark", callback.host == "auth", callback.path == "/callback" else {
            throw OiServiceError.invalidCallback
        }
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if query.contains(where: { $0.name == "error" && $0.value == "access_denied" }) { throw CancellationError() }
        if query.contains(where: { $0.name == "error" || $0.name == "error_code" }) {
            throw OiServiceError.authenticationFailed
        }
        guard let code = query.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { throw OiServiceError.invalidCallback }
        let session = try await api.session(grant: "pkce", payload: ["auth_code": code, "code_verifier": verifier])
        try Task.checkCancellation()
        return session
    }

    private func complete(_ attempt: UUID, result: Result<URL, Error>) {
        guard attemptID == attempt, let continuation else { return }
        self.continuation = nil
        webSession = nil; anchor = nil
        continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
