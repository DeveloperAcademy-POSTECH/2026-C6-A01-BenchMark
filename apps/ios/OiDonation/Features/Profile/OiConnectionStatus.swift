//
//  OiConnectionStatus.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import SwiftUI

struct OiConnectionStatus: View {
    let remote: OiRemoteStore
    var showsInitialProgress = true
    @State private var appleAuthentication = OiAppleAuthentication()

    var body: some View {
        let isLoading = showsInitialProgress && remote.isRefreshing && !remote.hasLoadedRemote
        if isLoading || remote.syncWarning != nil || remote.loadError != nil || remote.needsReauthentication {
            VStack(alignment: .leading, spacing: 8) {
                if isLoading { ProgressView().accessibilityLabel("서버에서 불러오는 중") }
                if let warning = remote.syncWarning { Label(warning, systemImage: "checkmark.icloud").font(.footnote).accessibilityIdentifier("oi.sync.warning") }
                if let error = remote.loadError {
                    Text(remote.hasLoadedRemote ? "연결을 확인하지 못해 마지막으로 불러온 내용을 표시합니다. \(error)" : "아직 목록을 불러오지 못했습니다. \(error)")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("oi.load.error")
                    Button("다시 불러오기") { Task { await remote.refresh() } }.disabled(remote.isBusy || remote.isRefreshing)
                }
                if remote.needsReauthentication {
                    Button("Google로 다시 인증") { Task { await remote.signIn() } }.disabled(remote.isBusy).accessibilityIdentifier("oi.auth.retry")
                    OiAppleSignInButton { Task { await remote.signIn(using: appleAuthentication) } }
                        .frame(minHeight: 44).disabled(remote.isBusy)
                }
            }
        }
    }
}
