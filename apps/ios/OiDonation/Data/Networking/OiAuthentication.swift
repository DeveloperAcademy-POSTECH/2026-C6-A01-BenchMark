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
        guard status == errSecSuccess, let data = value as? Data else { throw OiServiceError.unavailable }
        return try JSONDecoder().decode(OiSession.self, from: data)
    }

    func write(_ session: OiSession?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw OiServiceError.unavailable }
            return
        }
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var values = query
            values[kSecValueData as String] = data
            values[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else { throw OiServiceError.unavailable }
        } else if status != errSecSuccess { throw OiServiceError.unavailable }
    }
}

@MainActor
final class OiGoogleAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let callback = "kr.ac.postech.benchmark://auth/callback"
    private var webSession: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?

    func signIn(api: OiServiceAPI) async throws -> OiSession {
        guard webSession == nil else { throw OiServiceError.unavailable }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw OiServiceError.unavailable }
        let verifier = Data(random).base64URLEncoded
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow),
              var components = URLComponents(string: "https://\(OiServiceAPI.projectHost)/auth/v1/authorize") else { throw OiServiceError.unavailable }
        anchor = window
        components.queryItems = [URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Self.callback), URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")]
        guard let url = components.url else { throw OiServiceError.invalidCallback }
        defer { webSession = nil; anchor = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let authentication = ASWebAuthenticationSession(url: url, callbackURLScheme: "kr.ac.postech.benchmark") { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: OiServiceError.invalidCallback) }
            }
            authentication.presentationContextProvider = self
            webSession = authentication
            if !authentication.start() { continuation.resume(throwing: OiServiceError.unavailable) }
        }
        guard callback.scheme == "kr.ac.postech.benchmark", callback.host == "auth", callback.path == "/callback",
              let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { throw OiServiceError.invalidCallback }
        return try await api.session(grant: "pkce", payload: ["auth_code": code, "code_verifier": verifier])
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
