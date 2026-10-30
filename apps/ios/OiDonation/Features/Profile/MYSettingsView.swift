// Created by 이돈혁

import SwiftUI

struct MYSettingsView: View {
    let container: AppContainer
    let store: CampusStoryStore
    let demo: MYLibraryStore
    let onCamera: () -> Void
    var remote: OiRemoteStore?
    @Environment(\.openURL) private var openURL
    @State private var settingsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                NavigationLink { account } label: { row("닉네임 설정") }
                NavigationLink {
                    if let remote { MYSchoolSettings(remote: remote) }
                    else { ContentUnavailableView("로그인이 필요해요", systemImage: "person") }
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
        else { ContentUnavailableView("로그인이 필요해요", systemImage: "person") }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { settingsError = true; return }
        openURL(url) { accepted in if !accepted { settingsError = true } }
    }
}

private struct MYSchoolSettings: View {
    let remote: OiRemoteStore
    var body: some View {
        List {
            OiConnectionStatus(remote: remote)
            if remote.account == nil {
                NavigationLink("로그인하기") { OiAccountView(remote: remote) }
            } else {
                ForEach(remote.schools) { school in
                    Button {
                        Task { await remote.updateProfile(nickname: remote.profile?.nickname ?? "농부", schoolID: school.id) }
                    } label: {
                        HStack {
                            Text(school.name); Spacer()
                            if remote.profile?.schoolId == school.id { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44)
                    }.disabled(remote.isBusy)
                }
                if remote.schools.isEmpty { Text("등록된 학교가 없어요.") }
            }
            if let error = remote.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("학교 설정").navigationBarTitleDisplayMode(.inline)
    }
}
