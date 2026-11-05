//
//  OiSignInView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct OiSignInView: View {
    enum Presentation {
        case standard, settings
    }

    let remote: OiRemoteStore
    var showsProgress = true
    var presentation: Presentation = .standard

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingConnection = false
    @State private var appleAuthentication = OiAppleAuthentication()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OiConnectionStatus(remote: remote, showsInitialProgress: showsProgress && !remote.isBusy)

            if let error = remote.error, error != remote.loadError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("oi.signIn.error")
            }

            if presentation == .settings && !remote.needsReauthentication {
                settingsButtons
            } else if remote.account == nil && !remote.needsReauthentication {
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
        .navigationDestination(isPresented: $showingConnection) {
            OiAccountMergeView(remote: remote, mode: .addLoginMethod)
        }
        .onChange(of: remote.account?.id) { _, owner in
            if owner == nil { showingConnection = false }
        }
    }

    @ViewBuilder private var settingsButtons: some View {
        if dynamicTypeSize >= .xxxLarge {
            verticalSettingsButtons
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    settingsProvider("apple") { settingsAppleButton }.frame(width: 170)
                    settingsProvider("google") { settingsGoogleButton }.frame(width: 170)
                }
                .fixedSize(horizontal: true, vertical: false)
                verticalSettingsButtons
            }
        }
    }

    private var verticalSettingsButtons: some View {
        VStack(spacing: 20) {
            settingsProvider("apple") { settingsAppleButton }
            settingsProvider("google") { settingsGoogleButton }
        }
    }

    private var canConnect: Bool {
        remote.hasLoadedRemote && remote.isAccountMergeAvailable && !remote.isOperator && !remote.needsReauthentication
    }

    private func settingsProvider<Content: View>(_ provider: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
                .disabled(!remote.isConfigured || remote.isBusy ||
                    (remote.account != nil && (!canConnect || remote.accountProviders.contains(provider))))
            if remote.account != nil {
                Text(remote.accountProviders.contains(provider) ? "로그인 완료" :
                    (remote.accountProviders.isEmpty ? "연결 상태 확인 필요" : "추가 연동"))
                    .font(CampusStyle.body(12))
                    .foregroundStyle(remote.accountProviders.contains(provider) ? CampusStyle.green : .secondary)
            }
        }
    }

    private var settingsAppleButton: some View {
        OiAppleSignInButton {
            if remote.account != nil { showingConnection = true }
            else { Task { await remote.signIn(using: appleAuthentication) } }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }

    private var settingsGoogleButton: some View {
        Button {
            if remote.account != nil { showingConnection = true }
            else { Task { await remote.signIn() } }
        } label: {
            Text("Google로 로그인")
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(CampusStyle.green)
        .accessibilityIdentifier("oi.auth.google")
    }
}
