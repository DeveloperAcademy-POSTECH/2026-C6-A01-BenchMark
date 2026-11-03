// Created by 이돈혁

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class OiAppleAuthentication: NSObject, OiAuthenticating,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private var anchor: ASPresentationAnchor?
    private var continuation: CheckedContinuation<String, Error>?
    private var attempt: UUID?

    func signIn(api: OiServiceAPI) async throws -> OiSession {
        let credential = try await credentials()
        let session = try await api.session(grant: "id_token", payload: ["provider": "apple", "id_token": credential.token, "nonce": credential.nonce])
        try Task.checkCancellation()
        return session
    }

    private func credentials() async throws -> (token: String, nonce: String) {
        try Task.checkCancellation()
        guard attempt == nil else { throw OiServiceError.unavailable }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OiServiceError.unavailable
        }
        let nonce = Data(bytes).base64EncodedString()
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw OiServiceError.unavailable
        }
        let id = UUID()
        attempt = id
        anchor = window
        defer {
            if attempt == id { attempt = nil; controller = nil; continuation = nil; anchor = nil }
        }
        let token = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { pending in
                continuation = pending
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.email]
                request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
                let authorization = ASAuthorizationController(authorizationRequests: [request])
                authorization.delegate = self
                authorization.presentationContextProvider = self
                controller = authorization
                authorization.performRequests()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.attempt == id else { return }
                self.controller?.cancel()
                self.finish(.failure(CancellationError()))
            }
        }
        try Task.checkCancellation()
        return (token, nonce)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard self.controller === controller else { return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            finish(.failure(OiServiceError.invalidCallback)); return
        }
        finish(.success(token))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard self.controller === controller else { return }
        let failure = error as NSError
        if failure.domain == ASAuthorizationError.errorDomain, failure.code == ASAuthorizationError.canceled.rawValue {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(OiServiceError.server("Apple 로그인에 실패했습니다. 계정과 로그인 설정을 확인한 뒤 다시 시도해 주세요.")))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<String, Error>) {
        guard let pending = continuation else { return }
        continuation = nil
        controller = nil
        anchor = nil
        pending.resume(with: result)
    }
}
