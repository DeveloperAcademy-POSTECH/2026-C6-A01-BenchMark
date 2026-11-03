// Created by 이돈혁

import SwiftUI
import AVFoundation
import CoreLocation
import Photos
import UserNotifications

struct MYSettingsView: View {
    let container: AppContainer
    let store: CampusStoryStore
    let demo: MYLibraryStore
    let onCamera: () -> Void
    var remote: OiRemoteStore?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsError = false
    @State private var permissions: [MYPermissionStatus] = []

    private var schoolName: String {
        guard let id = remote?.profile?.schoolId else { return "학교를 선택해 주세요" }
        return remote?.schools.first { $0.id == id }?.name ?? "학교 정보 확인 중"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if let remote { OiConnectionStatus(remote: remote) }
                section("닉네임", detail: "띄어쓰기 포함 30자 이내") {
                    NavigationLink { account } label: {
                        editableCard(remote?.profile?.nickname ?? demo.nickname, action: "수정")
                    }.accessibilityIdentifier("my.settings.nickname")
                }
                section("학적정보") {
                    NavigationLink {
                        if let remote { MYSchoolSettings(remote: remote) }
                        else { ContentUnavailableView("로그인이 필요해요", systemImage: "person") }
                    } label: {
                        editableCard(schoolName, prefix: "학교", action: "수정")
                    }.accessibilityIdentifier("my.settings.school")
                }
                section("권한허용") {
                    VStack(spacing: 4) {
                        ForEach(permissions) { permission in
                            Button { openAppSettings() } label: {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) { permissionTitle(permission); Spacer(minLength: 8); permissionValue(permission) }
                                    VStack(alignment: .leading, spacing: 8) { permissionTitle(permission); permissionValue(permission) }
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 20).padding(.vertical, 6)
                            }.accessibilityLabel("\(permission.title), \(permission.value), iPhone 설정에서 변경")
                        }
                    }
                    Text("권한은 iPhone 설정에서 변경할 수 있어요.")
                        .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                }
                section("로그인 계정") {
                    NavigationLink { account } label: {
                        editableCard(remote?.account?.email ?? (remote?.account == nil ? "로그인하기" : "로그인한 계정"), action: "관리")
                    }.accessibilityIdentifier("my.settings.account")
                }
                NavigationLink {
                    CampusProfileMenu(container: container, store: store, onCamera: onCamera, remote: remote)
                } label: {
                    Label("기존 메뉴 · 촬영 · 수집 목록", systemImage: "square.grid.2x2")
                        .font(CampusStyle.body(16)).frame(minHeight: 44)
                }
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 30)
        }
        .background(Color.white.ignoresSafeArea()).foregroundStyle(.black)
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) {
            Text("설정").font(.custom("Paperlogy-7Bold", size: 30, relativeTo: .title))
                .foregroundStyle(Color(red: 117 / 255, green: 75 / 255, blue: 0))
        } }
        .task(id: scenePhase) { if scenePhase == .active { await refreshPermissions() } }
        .alert("설정을 열 수 없어요", isPresented: $settingsError) {
            Button("확인", role: .cancel) {}
        } message: { Text("iPhone의 설정 앱에서 오이기부의 권한과 위치 접근을 확인해 주세요.") }
    }

    private func section<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) { sectionTitle(title); sectionDetail(detail) }
                VStack(alignment: .leading, spacing: 6) { sectionTitle(title); sectionDetail(detail) }
            }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value).font(CampusStyle.semibold(26)).accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func sectionDetail(_ value: String?) -> some View {
        if let value { Text(value).font(.custom("Paperlogy-3Light", size: 16, relativeTo: .body)).foregroundStyle(CampusStyle.green) }
    }

    private func editableCard(_ value: String, prefix: String? = nil, action: String) -> some View {
        HStack(spacing: 12) {
            if let prefix { Text(prefix).font(CampusStyle.semibold(18)) }
            Text(value).font(CampusStyle.semibold(18)).frame(maxWidth: .infinity, alignment: .leading)
            Text(action).font(.system(size: 18, weight: .light)).foregroundStyle(CampusStyle.green)
        }.foregroundStyle(CampusStyle.sectionGreen)
            .padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity, minHeight: 60)
            .background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 15))
            .contentShape(RoundedRectangle(cornerRadius: 15))
    }

    private func permissionTitle(_ permission: MYPermissionStatus) -> some View {
        Text(permission.title).font(.custom("Paperlogy-3Light", size: 20, relativeTo: .body)).foregroundStyle(.black)
    }

    private func permissionValue(_ permission: MYPermissionStatus) -> some View {
        HStack(spacing: 6) {
            Text(permission.value).font(CampusStyle.body(14))
            Image(systemName: "chevron.right").font(.caption)
        }.foregroundStyle(CampusStyle.sectionGreen)
    }

    @MainActor private func refreshPermissions() async {
        let notification = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        let notifications: String
        switch notification.authorizationStatus {
        case .authorized: notifications = "허용됨"
        case .provisional, .ephemeral: notifications = "일부 허용"
        case .denied: notifications = "허용 안 함"
        case .notDetermined: notifications = "요청 전"
        @unknown default: notifications = "확인 필요"
        }
        let location: String
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: location = "항상 허용"
        case .authorizedWhenInUse: location = "사용 중 허용"
        case .denied, .restricted: location = "허용 안 함"
        case .notDetermined: location = "요청 전"
        @unknown default: location = "확인 필요"
        }
        let camera: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = "허용됨"
        case .denied, .restricted: camera = "허용 안 함"
        case .notDetermined: camera = "요청 전"
        @unknown default: camera = "확인 필요"
        }
        let photos: String
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: photos = "모든 사진 허용"
        case .limited: photos = "선택한 사진 허용"
        case .denied, .restricted: photos = "허용 안 함"
        case .notDetermined: photos = "요청 전"
        @unknown default: photos = "확인 필요"
        }
        permissions = [MYPermissionStatus(title: "알림", value: notifications), MYPermissionStatus(title: "위치 정보", value: location),
                       MYPermissionStatus(title: "카메라 접근", value: camera), MYPermissionStatus(title: "사진 접근", value: photos)]
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

private struct MYPermissionStatus: Identifiable {
    let title: String
    let value: String
    var id: String { title }
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
