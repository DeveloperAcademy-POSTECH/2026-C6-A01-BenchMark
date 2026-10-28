// Created by 이돈혁

import SwiftUI

struct OiConnectionStatus: View {
    let remote: OiRemoteStore

    var body: some View {
        if remote.isRefreshing || remote.syncWarning != nil || remote.loadError != nil || remote.needsReauthentication {
        VStack(alignment: .leading, spacing: 8) {
            if remote.isRefreshing { ProgressView(remote.hasLoadedRemote ? "최신 상태 확인 중" : "서버에서 불러오는 중") }
            if let warning = remote.syncWarning { Label(warning, systemImage: "checkmark.icloud").font(.footnote).accessibilityIdentifier("oi.sync.warning") }
            if let error = remote.loadError {
                Text(remote.hasLoadedRemote ? "연결을 확인하지 못해 마지막으로 불러온 내용을 표시합니다. \(error)" : "아직 목록을 불러오지 못했습니다. \(error)")
                    .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("oi.load.error")
                Button("다시 불러오기") { Task { await remote.refresh() } }.disabled(remote.isBusy || remote.isRefreshing)
            }
            if remote.needsReauthentication {
                Button("Google 계정 다시 인증") { Task { await remote.signIn() } }.disabled(remote.isBusy).accessibilityIdentifier("oi.auth.retry")
            }
        }
        }
    }
}
