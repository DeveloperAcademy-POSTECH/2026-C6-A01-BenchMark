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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var settingsError = false
    @State private var permissionValues: [MYPermission: PermissionStatus] = [:]
    @State private var editingSchoolOwner: UUID?
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
        return remote?.schools.first { $0.id == id }?.name ?? "학교 정보 없음"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                section("닉네임", detail: "띄어쓰기 포함 30자 이내") {
                    nicknameRow
                }
                section("내 농장 이름") {
                    settingsCard {
                        if dynamicTypeSize.isAccessibilitySize {
                            profileValue(nickname + "의 밭")
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                profileValue(nickname)
                                Text("의 밭")
                                    .font(.custom("Paperlogy-4Regular", size: 18, relativeTo: .body))
                                    .foregroundStyle(Color(red: 139 / 255, green: 98 / 255, blue: 53 / 255))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }.accessibilityIdentifier("my.settings.farm")
                }
                section("학적정보") { schoolRow }
                section("권한허용", detail: "iPhone 설정에서 변경") {
                    if permissionValues.count < MYPermission.allCases.count {
                        ProgressView().accessibilityLabel("기기 권한 확인 중")
                    }
                    VStack(spacing: 0) {
                        ForEach(MYPermission.allCases, id: \.self) { permission in
                            permissionRow(permission)
                        }
                    }
                }
                section("로그인 계정") {
                    if let remote {
                        if let account = remote.account {
                            editableCard(account.email ?? "로그인한 계정")
                                .accessibilityIdentifier("my.settings.account")
                        }
                        OiSignInView(remote: remote, showsProgress: editingSchoolOwner == nil || remote.needsReauthentication)
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
        .onChange(of: remote?.account?.id) { _, _ in
            resetNicknameEditor()
            editingSchoolOwner = nil
        }
        .alert("설정을 열 수 없어요", isPresented: $settingsError) {
            Button("확인", role: .cancel) {}
        } message: { Text("iPhone의 설정 앱에서 오이기부의 권한과 위치 접근을 확인해 주세요.") }
    }

    @ViewBuilder private var nicknameRow: some View {
        if let remote, let owner = remote.account?.id, remote.hasLoadedRemote, !remote.needsReauthentication {
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
            editableCard(nickname).accessibilityIdentifier("my.settings.nickname")
        }
    }

    private func saveNickname(remote: OiRemoteStore) {
        let value = cleanedNickname
        guard let owner = nicknameOwner, remote.account?.id == owner, remote.hasLoadedRemote, !remote.isBusy,
              !remote.needsReauthentication, !value.isEmpty, value.count <= 30 else { return }
        nicknameError = nil
        Task {
            guard remote.account?.id == owner, nicknameOwner == owner, remote.hasLoadedRemote,
                  !remote.needsReauthentication, !remote.isBusy else { return }
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
        if let value { Text(value).font(.custom("Paperlogy-3Light", size: 16, relativeTo: .body)).tracking(0.32).foregroundStyle(CampusStyle.green) }
    }

    private func profileValue(_ value: String) -> some View {
        Text(value).font(CampusStyle.semibold(18)).tracking(0.36)
            .foregroundStyle(CampusStyle.sectionGreen)
    }

    private func editableCard(_ value: String, action: String? = nil) -> some View {
        settingsCard(action: action) { profileValue(value) }
    }

    @ViewBuilder private var schoolRow: some View {
        if let remote, let owner = remote.account?.id, !remote.needsReauthentication {
            if editingSchoolOwner == owner {
                schoolEditor(remote: remote, owner: owner)
            } else {
                Button { editingSchoolOwner = owner } label: { schoolCard(action: "수정") }
                    .accessibilityIdentifier("my.settings.school")
            }
        } else {
            schoolCard().accessibilityIdentifier("my.settings.school")
        }
    }

    private func schoolEditor(remote: OiRemoteStore, owner: UUID) -> some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    profileValue("학교")
                    Spacer()
                    Button("취소") { editingSchoolOwner = nil }
                        .foregroundStyle(CampusStyle.green)
                        .frame(minHeight: 44)
                }
                OiConnectionStatus(remote: remote, showsInitialProgress: !remote.isBusy)
                if remote.isBusy { ProgressView().accessibilityLabel("학교 저장 중") }
                if remote.schools.isEmpty, remote.hasLoadedRemote {
                    Text("등록된 학교가 없어요.").font(.footnote)
                }
                ForEach(remote.schools) { school in
                    Button {
                        Task {
                            guard remote.account?.id == owner, editingSchoolOwner == owner, remote.hasLoadedRemote,
                                  !remote.needsReauthentication, !remote.isBusy else { return }
                            await remote.updateProfile(nickname: remote.profile?.nickname ?? "농부", schoolID: school.id)
                            guard remote.account?.id == owner, remote.profile?.schoolId == school.id,
                                  remote.error == nil else { return }
                            editingSchoolOwner = nil
                        }
                    } label: {
                        HStack {
                            Text(school.name)
                            Spacer()
                            if remote.profile?.schoolId == school.id { Image(systemName: "checkmark") }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .disabled(!remote.hasLoadedRemote || remote.needsReauthentication)
                    .accessibilityAddTraits(remote.profile?.schoolId == school.id ? .isSelected : [])
                }
                if let error = remote.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.disabled(remote.isBusy)
        }
    }

    private func schoolCard(action: String? = nil) -> some View {
        settingsCard(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 11))
            layout {
                profileValue("학교")
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("|").foregroundStyle(CampusStyle.sectionGreen).accessibilityHidden(true)
                }
                Text(schoolName)
                    .font(.custom("Paperlogy-4Regular", size: 18, relativeTo: .body))
            }.accessibilityElement(children: .combine)
        }
    }

    private func settingsCard<Content: View>(action: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            content().frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Text(action).font(.system(size: 18, weight: .light)).foregroundStyle(CampusStyle.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 15))
        .contentShape(RoundedRectangle(cornerRadius: 15))
    }

    private func permissionRow(_ permission: MYPermission) -> some View {
        let status = permissionValues[permission]
        return Button(action: openAppSettings) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    permissionTitle(permission.title)
                    Spacer(minLength: 8)
                    permissionIndicator(status)
                }
                VStack(alignment: .leading, spacing: 8) {
                    permissionTitle(permission.title)
                    permissionIndicator(status)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(permission.title)
        .accessibilityValue(status?.label ?? "")
        .accessibilityHint("iPhone 설정에서 변경")
    }

    private func permissionTitle(_ title: String) -> some View {
        Text(title).font(.custom("Paperlogy-3Light", size: 20, relativeTo: .body))
            .tracking(0.4).foregroundStyle(.black)
    }

    private func permissionIndicator(_ status: PermissionStatus?) -> some View {
        ZStack {
            if let isGranted = status?.isGranted {
                Capsule().fill(isGranted ? CampusStyle.green : Color(uiColor: .tertiaryLabel))
                    .overlay(alignment: isGranted ? .trailing : .leading) {
                        Capsule().fill(.white).frame(width: 38, height: 24).padding(.horizontal, 2)
                    }
            }
        }
        .frame(width: 64, height: 28)
        .accessibilityHidden(true)
    }

    private struct PermissionStatus {
        let label: String
        let isGranted: Bool?
    }

    @MainActor private func refreshPermissions() async {
        let location: PermissionStatus
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: location = .init(label: "항상 허용", isGranted: true)
        case .authorizedWhenInUse: location = .init(label: "사용 중 허용", isGranted: true)
        case .denied, .restricted: location = .init(label: "허용 안 함", isGranted: false)
        case .notDetermined: location = .init(label: "요청 전", isGranted: false)
        @unknown default: location = .init(label: "확인 필요", isGranted: nil)
        }
        let camera: PermissionStatus
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = .init(label: "허용됨", isGranted: true)
        case .denied, .restricted: camera = .init(label: "허용 안 함", isGranted: false)
        case .notDetermined: camera = .init(label: "요청 전", isGranted: false)
        @unknown default: camera = .init(label: "확인 필요", isGranted: nil)
        }
        let photos: PermissionStatus
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: photos = .init(label: "모든 사진 허용", isGranted: true)
        case .limited: photos = .init(label: "선택한 사진 허용", isGranted: true)
        case .denied, .restricted: photos = .init(label: "허용 안 함", isGranted: false)
        case .notDetermined: photos = .init(label: "요청 전", isGranted: false)
        @unknown default: photos = .init(label: "확인 필요", isGranted: nil)
        }
        permissionValues[.location] = location
        permissionValues[.camera] = camera
        permissionValues[.photos] = photos

        let notification = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        switch notification.authorizationStatus {
        case .authorized: permissionValues[.notifications] = .init(label: "허용됨", isGranted: true)
        case .provisional, .ephemeral: permissionValues[.notifications] = .init(label: "일부 허용", isGranted: true)
        case .denied: permissionValues[.notifications] = .init(label: "허용 안 함", isGranted: false)
        case .notDetermined: permissionValues[.notifications] = .init(label: "요청 전", isGranted: false)
        @unknown default: permissionValues[.notifications] = .init(label: "확인 필요", isGranted: nil)
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
