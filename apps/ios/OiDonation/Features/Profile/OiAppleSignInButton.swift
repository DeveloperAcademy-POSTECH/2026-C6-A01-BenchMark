// Created by 이돈혁

import AuthenticationServices
import SwiftUI

struct OiAppleSignInButton: UIViewRepresentable {
    let action: () -> Void
    var type: ASAuthorizationAppleIDButton.ButtonType = .signIn

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: type, style: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn), for: .touchUpInside)
        button.accessibilityIdentifier = "oi.auth.apple"
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func signIn() { action() }
    }
}
