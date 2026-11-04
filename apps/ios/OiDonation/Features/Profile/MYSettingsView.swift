// Created by 이돈혁

import SwiftUI
import AVFoundation
import CoreLocation
import Photos
import UserNotifications

struct MYSettingsView: View {
    var demo: MYLibraryStore? = nil
    let remote: OiRemoteStore?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsError = false
    @State private var permissionValues: [MYPermission: String] = [:]
    @State private var nicknameOwner: UUID?
    @State private var nicknameInput = ""
    @State private var nicknameError: String?
    @FocusState private var nicknameFocused: Bool

    private var nickname: String {
        if let remote { return remote.profile?.nickname ?? "농부" }
        return demo?.nickname ?? "농부"
    }
    private var cleanedNickname: String { nicknameInput.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var schoolName: String {
        guard let id = remote?.profile?.schoolId else { return "학교를 선택해 주세요" }
        return remote?.schools.first { $0.id == id }?.name ?? "학교 정보 확인 중"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                section("닉네임", detail: "띄어쓰기 포함 30자 이내") {
                    nicknameRow
                }
                section("학적정보") {
                    if let remote, remote.account != nil, !remote.needsReauthentication {
                        NavigationLink { MYSchoolSettings(remote: remote) } label: {
                            editableCard(schoolName, prefix: "학교", action: "수정")
                        }.accessibilityIdentifier("my.settings.school")
                    } else {
                        editableCard(schoolName, prefix: "학교", action: "로그인 후 수정")
                            .accessibilityIdentifier("my.settings.school")
                    }
                }
                section("권한허용") {
                    VStack(spacing: 0) {
                        ForEach(MYPermission.allCases, id: \.self) { permission in
                            let value = permissionValues[permission] ?? "확인 중"
                            Button { openAppSettings() } label: {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) { permissionTitle(permission.title); Spacer(minLength: 8); permissionValue(value) }
                                    VStack(alignment: .leading, spacing: 8) { permissionTitle(permission.title); permissionValue(value) }
                                }.padding(.horizontal, 20)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.accessibilityLabel("\(permission.title), \(value), iPhone 설정에서 변경")
                        }
                    }
                    Text("권한은 iPhone 설정에서 변경할 수 있어요.")
                        .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                }
                section("로그인 계정") {
                    if let remote {
                        if let account = remote.account {
                            editableCard(account.email ?? "로그인한 계정")
                                .accessibilityIdentifier("my.settings.account")
                        }
                        OiSignInView(remote: remote)
                        if remote.account != nil {
                            Button(role: .destructive) {
                                Task { await remote.signOut() }
                            } label: {
                                Text("로그아웃").frame(minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(remote.isBusy)
                            .accessibilityIdentifier("oi.auth.signOut")
                        }
                    } else {
                        editableCard("로그인이 필요해요").accessibilityIdentifier("my.settings.account")
                    }
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
        .onChange(of: remote?.account?.id) { _, _ in resetNicknameEditor() }
        .alert("설정을 열 수 없어요", isPresented: $settingsError) {
            Button("확인", role: .cancel) {}
        } message: { Text("iPhone의 설정 앱에서 오이기부의 권한과 위치 접근을 확인해 주세요.") }
    }

    @ViewBuilder private var nicknameRow: some View {
        if let remote, let owner = remote.account?.id, !remote.needsReauthentication {
            if nicknameOwner == owner {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("닉네임", text: $nicknameInput)
                        .font(CampusStyle.semibold(18))
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($nicknameFocused)
                        .onAppear { nicknameFocused = true }
                        .onSubmit { saveNickname(remote: remote) }
                        .accessibilityIdentifier("my.settings.nickname.input")
                    if let nicknameError { Text(nicknameError).font(.footnote).foregroundStyle(.secondary) }
                    HStack {
                        Button("취소", role: .cancel, action: resetNicknameEditor)
                            .buttonStyle(.bordered)
                        Button("저장") { saveNickname(remote: remote) }
                            .buttonStyle(.borderedProminent)
                            .tint(CampusStyle.green)
                            .disabled(cleanedNickname.isEmpty || cleanedNickname.count > 30)
                            .accessibilityIdentifier("my.settings.nickname.save")
                    }
                }
                .disabled(remote.isBusy)
                .padding(.horizontal, 20).padding(.vertical, 18)
                .background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 15))
            } else {
                Button {
                    nicknameInput = nickname
                    nicknameOwner = owner
                } label: {
                    editableCard(nickname, action: "수정")
                }.accessibilityIdentifier("my.settings.nickname")
            }
        } else {
            editableCard(nickname, action: "로그인 후 수정").accessibilityIdentifier("my.settings.nickname")
        }
    }

    private func saveNickname(remote: OiRemoteStore) {
        let value = cleanedNickname
        guard let owner = nicknameOwner, remote.account?.id == owner, !remote.isBusy,
              !remote.needsReauthentication, !value.isEmpty, value.count <= 30 else { return }
        nicknameError = nil
        Task {
            guard remote.account?.id == owner, nicknameOwner == owner, !remote.isBusy else { return }
            await remote.updateProfile(nickname: value)
            guard remote.account?.id == owner, nicknameOwner == owner else { return }
            if let error = remote.error { nicknameError = error }
            else { resetNicknameEditor() }
        }
    }

    private func resetNicknameEditor() {
        nicknameFocused = false
        nicknameOwner = nil
        nicknameInput = ""
        nicknameError = nil
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

    private func editableCard(_ value: String, prefix: String? = nil, action: String? = nil) -> some View {
        HStack(spacing: 12) {
            if let prefix { Text(prefix).font(CampusStyle.semibold(18)) }
            Text(value).font(CampusStyle.semibold(18)).frame(maxWidth: .infinity, alignment: .leading)
            if let action { Text(action).font(.system(size: 18, weight: .light)).foregroundStyle(CampusStyle.green) }
        }.foregroundStyle(CampusStyle.sectionGreen)
            .padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity, minHeight: 60)
            .background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 15))
            .contentShape(RoundedRectangle(cornerRadius: 15))
    }

    private func permissionTitle(_ title: String) -> some View {
        Text(title).font(.custom("Paperlogy-3Light", size: 20, relativeTo: .body)).foregroundStyle(.black)
    }

    private func permissionValue(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value).font(CampusStyle.body(14))
            Image(systemName: "chevron.right").font(.caption)
        }.foregroundStyle(CampusStyle.sectionGreen)
    }

    @MainActor private func refreshPermissions() async {
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
        permissionValues[.location] = location
        permissionValues[.camera] = camera
        permissionValues[.photos] = photos

        let notification = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        switch notification.authorizationStatus {
        case .authorized: permissionValues[.notifications] = "허용됨"
        case .provisional, .ephemeral: permissionValues[.notifications] = "일부 허용"
        case .denied: permissionValues[.notifications] = "허용 안 함"
        case .notDetermined: permissionValues[.notifications] = "요청 전"
        @unknown default: permissionValues[.notifications] = "확인 필요"
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { settingsError = true; return }
        openURL(url) { accepted in if !accepted { settingsError = true } }
    }
}

private enum MYPermission: CaseIterable, Hashable {
    case notifications, location, camera, photos

    var title: String {
        switch self {
        case .notifications: "알림"
        case .location: "위치 정보"
        case .camera: "카메라 접근"
        case .photos: "사진 접근"
        }
    }
}

private struct MYSchoolSettings: View {
    let remote: OiRemoteStore
    var body: some View {
        List {
            if remote.account == nil || remote.needsReauthentication {
                ContentUnavailableView("로그인이 필요해요", systemImage: "person",
                    description: Text("설정의 로그인 계정에서 로그인한 뒤 학교를 선택해 주세요."))
            } else {
                OiConnectionStatus(remote: remote)
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
