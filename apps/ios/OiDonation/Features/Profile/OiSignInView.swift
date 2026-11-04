//
//  OiSignInView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct OiSignInView: View {
    let remote: OiRemoteStore
    var showsProgress = true

    @State private var appleAuthentication = OiAppleAuthentication()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OiConnectionStatus(remote: remote, showsInitialProgress: showsProgress && !remote.isBusy)

            if let error = remote.error, error != remote.loadError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("oi.signIn.error")
            }

            if remote.account == nil && !remote.needsReauthentication {
                Button { Task { await remote.signIn() } } label: {
                    Text("Google로 로그인").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(CampusStyle.green)
                .disabled(!remote.isConfigured || remote.isBusy)
                .accessibilityIdentifier("oi.auth.google")
                OiAppleSignInButton { Task { await remote.signIn(using: appleAuthentication) } }
                    .frame(height: 44)
                    .disabled(!remote.isConfigured || remote.isBusy)
            }
            if showsProgress && remote.isBusy { ProgressView().accessibilityLabel("처리 중") }
        }
    }
}
