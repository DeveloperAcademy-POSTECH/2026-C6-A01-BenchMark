// Created by 이돈혁

import SwiftUI

struct MYSettingsView: View {
    let container: AppContainer
    let store: CampusStoryStore
    let demo: MYDemoStore
    let onCamera: () -> Void
    var remote: OiRemoteStore?
    @Environment(\.openURL) private var openURL
    @State private var settingsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                NavigationLink { account } label: { row("닉네임 설정") }
                NavigationLink {
                    List {
                        Label("POSTECH", systemImage: "checkmark")
                        Text("현재는 POSTECH 캠퍼스만 지원해요.").font(.footnote).foregroundStyle(.secondary)
                    }.navigationTitle("학교 설정")
                } label: { row("학교 설정") }
                Button { openAppSettings() } label: { row("권한 허용") }
                NavigationLink { account } label: { row("로그인 계정") }
                Button { openAppSettings() } label: { row("위치설정") }
                NavigationLink {
                    CampusProfileMenu(container: container, store: store, onCamera: onCamera, remote: remote)
                } label: { Text("기존 메뉴 · 촬영 · 수집 목록").font(.footnote).frame(minHeight: 44) }
            }.padding(.horizontal, 42).padding(.top, 20)
        }
        .background(Color.white.ignoresSafeArea()).foregroundStyle(.black)
        .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .alert("설정을 열 수 없어요", isPresented: $settingsError) {
            Button("확인", role: .cancel) {}
        } message: { Text("iPhone의 설정 앱에서 오이기부의 권한과 위치 접근을 확인해 주세요.") }
    }

    private func row(_ title: String) -> some View {
        Text(title).font(.custom("Paperlogy-6SemiBold", size: 20, relativeTo: .headline))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }

    @ViewBuilder private var account: some View {
        if let remote { OiAccountView(remote: remote) }
        else { ContentUnavailableView("디자인 예시 프로필", systemImage: "person", description: Text("현재 닉네임은 \(demo.nickname)입니다. 실제 계정 설정은 서비스 모드에서 로그인 후 사용할 수 있어요.")) }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { settingsError = true; return }
        openURL(url) { accepted in if !accepted { settingsError = true } }
    }
}
