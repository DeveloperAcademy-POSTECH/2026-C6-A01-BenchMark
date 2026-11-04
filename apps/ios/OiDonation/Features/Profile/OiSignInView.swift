//
//  OiSignInView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct OiSignInView: View {
    let remote: OiRemoteStore

    @State private var appleAuthentication = OiAppleAuthentication()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OiConnectionStatus(remote: remote)

            if let error = remote.error, error != remote.loadError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("oi.signIn.error")
            }

            if remote.account == nil && !remote.needsReauthentication {
                Text("로그인하면 수집한 오이와 즐겨찾기, 내 이야기가 계정에 저장됩니다.")
                    .font(.footnote).foregroundStyle(.secondary)
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
            if remote.isBusy { ProgressView("처리 중") }
        }
    }
}
