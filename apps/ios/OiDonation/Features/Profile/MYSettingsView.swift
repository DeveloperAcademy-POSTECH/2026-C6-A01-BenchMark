//
//  MYSettingsView.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/30/26.
//

import SwiftUI
import AVFoundation
import CoreLocation
import Photos
import UserNotifications

struct MYSettingsView: View {
    var demo: MYLibraryStore? = nil
    let remote: OiRemoteStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var settingsError = false
    @State private var showingBlockedAuthors = false
    @State private var showingSupport = false
    @State private var showingAcademicEditor = false
    @State private var featureUsage = OiFeatureUsage.shared
    @State private var pendingPermissionToEnable: MYPermission?
    @State private var locationPermission = MYLocationPermission()
    @State private var permissionInFlight: MYPermission?
    @State private var permissionTask: Task<Void, Never>?
    @State private var permissionError: String?
    @State private var permissionValues: [MYPermission: PermissionStatus] = [:]
    @State private var showingOperator = false
    @State private var confirmingDeletion = false
    @State private var deletionInProgress = false
    @State private var deletionNotice: String?
    @State private var deletionSucceeded = false
    @State private var deletionAppleAuthentication = OiAppleAuthentication()

    private var schoolName: String {
        guard let id = remote?.profile?.schoolId else { return "학교를 선택해 주세요" }
        return remote?.schools.first { $0.id == id }?.name ?? "학교 정보 없음"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                section("소셜 로그인") {
                    if let remote {
                        OiSignInView(remote: remote, presentation: .settings)
                    }
                }
                if remote?.account != nil || demo != nil {
                    section("학적정보") {
                        schoolRow
                        if let remote, let owner = remote.account?.id, remote.hasLoadedRemote {
                            Button { showingAcademicEditor = true } label: {
                                settingsCard(action: "수정") {
                                    Text("기부자 검색 정보").font(CampusStyle.medium(18))
                                }
                            }
                            .disabled(remote.needsReauthentication || remote.isBusy)
                            .accessibilityIdentifier("my.settings.academic.edit")
                            .sheet(isPresented: $showingAcademicEditor) {
                                OiPublicAcademicEditor(remote: remote, owner: owner)
                            }
                        }
                    }
                    section("권한허용", detail: "권한 허용 후 앱 안에서 켜고 끄기") {
                        if permissionValues.count < MYPermission.allCases.count {
                            ProgressView().accessibilityLabel("기기 권한 확인 중")
                        }
                        VStack(spacing: 0) {
                            ForEach(MYPermission.allCases, id: \.self) { permission in
                                permissionRow(permission)
                            }
                        }
                    }
                    if let remote, remote.isOperator, !remote.needsReauthentication {
                        section("운영자") {
                            Button { showingOperator = true } label: {
                                settingsCard(action: "열기") {
                                    Label("운영자 관리", systemImage: "person.badge.shield.checkmark")
                                }
                            }.accessibilityIdentifier("my.settings.operator")
                        }
                    }
                }
                section("콘텐츠 보호") {
                    Button("차단한 작성자") { showingBlockedAuthors = true }.frame(minHeight: 44)
                }
                section("도움말") {
                    Button("개인정보 및 지원") { showingSupport = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("my.settings.support")
                }
                if remote?.account != nil || demo != nil {
                    VStack(alignment: .leading, spacing: 0) {
                        if let remote {
                            Button(role: .destructive) {
                                Task { await remote.signOut() }
                            } label: {
                                Text("로그아웃")
                                    .font(CampusStyle.medium(16))
                                    .foregroundStyle(Color(white: 156 / 255))
                                    .frame(minHeight: 44)
                            }
                            .disabled(remote.isBusy)
                            .accessibilityIdentifier("oi.auth.signOut")
                        }
                        Button(remote?.isAccountDeletionPending == true ? "탈퇴 이어서 완료" : "회원 탈퇴", role: .destructive) {
                            confirmingDeletion = true
                        }
                            .font(CampusStyle.medium(16))
                            .foregroundStyle(Color(white: 156 / 255))
                            .frame(minHeight: 44)
                            .disabled(remote?.account == nil || remote?.isBusy == true || remote?.isRefreshing == true || remote?.needsReauthentication == true)
                            .accessibilityIdentifier("my.settings.deleteAccount")
                    }
                }
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 17).padding(.bottom, 40)
        }
        .sheet(isPresented: $showingBlockedAuthors) { OiBlockedAuthorsView() }
        .sheet(isPresented: $showingSupport) { OiSupportView() }
        .background(Color.white.ignoresSafeArea()).foregroundStyle(.black)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            OiSettingsHeader(title: "설정", back: { dismiss() })
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await refreshPermissions()
                completePendingPermission()
            }
        }
        .onChange(of: locationPermission.status) { _, status in
            permissionValues[.location] = locationStatus(status)
            completePendingPermission()
        }
        .onDisappear {
            permissionTask?.cancel()
            permissionTask = nil
            permissionInFlight = nil
        }
        .alert("권한 요청 실패", isPresented: Binding(
            get: { permissionError != nil }, set: { if !$0 { permissionError = nil } }
        )) {
            Button("확인", role: .cancel) { permissionError = nil }
        } message: { Text(permissionError ?? "권한을 확인해 주세요.") }
        .sheet(isPresented: $showingOperator) {
            if let remote { OiOperatorHomeView(remote: remote) }
        }
        .onChange(of: remote?.account?.id) { _, _ in
            showingOperator = false
            showingAcademicEditor = false
        }
        .confirmationDialog("회원 탈퇴", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            if remote?.accountProviders.isEmpty == true || remote?.accountProviders.contains("apple") == true {
                Button("Apple로 본인 확인 후 탈퇴", role: .destructive) { deleteAccount(using: deletionAppleAuthentication) }
            }
            if remote?.accountProviders.isEmpty == true || remote?.accountProviders.contains("google") == true {
                Button("Google로 본인 확인 후 탈퇴", role: .destructive) { deleteAccount(using: OiGoogleAuthentication()) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("연결된 로그인 계정, 이야기, 사진, 기존에 제출한 기부 증빙과 수집 기록이 모두 삭제됩니다. 되돌릴 수 없으며 실제 기부 내역에는 영향이 없습니다.")
        }
        .alert(deletionSucceeded ? "회원 탈퇴 완료" : "탈퇴 상태 확인", isPresented: Binding(
            get: { deletionNotice != nil }, set: { if !$0 { deletionNotice = nil } }
        )) {
            Button("확인", role: .cancel) { deletionNotice = nil }
        } message: { Text(deletionNotice ?? "") }
        .interactiveDismissDisabled(deletionInProgress)
        .alert("설정을 열 수 없어요", isPresented: $settingsError) {
            Button("확인", role: .cancel) {}
        } message: { Text("iPhone의 설정 앱에서 오이기부의 권한과 위치 접근을 확인해 주세요.") }
    }

    private func deleteAccount(using provider: any OiAuthenticating) {
        guard let remote, !deletionInProgress else { return }
        deletionInProgress = true
        deletionSucceeded = false
        Task {
            defer { deletionInProgress = false }
            do {
                let receipt = try await remote.deleteAccount(using: provider)
                deletionSucceeded = true
                var message = remote.syncWarning ?? "연결 계정과 오이기부 데이터가 삭제됐어요."
                if receipt.appleRevocationRequired {
                    message += "\nApple 로그인 연결을 자동으로 해제하지 못했어요. iPhone 설정 → Apple 계정 → Apple로 로그인 → 오이기부 → 사용 중단을 선택해 주세요."
                }
                deletionNotice = message
            } catch where OiServiceFailure.isCancellation(error) {
                return
            } catch {
                deletionNotice = "탈퇴 완료를 확인하지 못했어요. 현재 계정으로 다시 인증해 탈퇴를 이어서 진행해 주세요."
            }
        }
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
        Text(value).font(CampusStyle.medium(20)).accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func sectionDetail(_ value: String?) -> some View {
        if let value { Text(value).font(.custom("Paperlogy-3Light", size: 12, relativeTo: .caption)).tracking(0.24).foregroundStyle(CampusStyle.green) }
    }

    @ViewBuilder private var schoolRow: some View {
        if let remote {
            NavigationLink {
                OiSchoolEvidenceView(remote: remote)
            } label: {
                VStack(spacing: 4) {
                    Text("학교 자료 확인하기")
                        .font(CampusStyle.semibold(18))
                        .tracking(0.36)
                        .foregroundStyle(CampusStyle.green)
                    Text("대학 합격 인증 / 학생증 / 재학증명서 / 졸업증명서")
                        .font(CampusStyle.body(12))
                        .tracking(0.24)
                        .foregroundStyle(Color(white: 121 / 255))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 91)
                .background(Color(white: 243 / 255), in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).stroke(Color(white: 205 / 255), lineWidth: 1) }
            }
            .disabled(remote.needsReauthentication || remote.isBusy)
            .accessibilityValue(schoolName)
            .accessibilityIdentifier("my.settings.school")
        }
    }

    private func settingsCard<Content: View>(action: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            content().frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Text(action).font(.system(size: 16, weight: .light)).underline().foregroundStyle(Color(white: 61 / 255))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color(white: 243 / 255), in: RoundedRectangle(cornerRadius: 15))
        .contentShape(RoundedRectangle(cornerRadius: 15))
    }

    private func permissionRow(_ permission: MYPermission) -> some View {
        let status = permissionValues[permission]
        return Button {
            permissionTask = Task { await changePermission(permission) }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        permissionTitle(permission.title)
                        Text(permissionLabel(permission, status: status))
                            .font(CampusStyle.body(12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    permissionIndicator(status, feature: permission)
                }
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        permissionTitle(permission.title)
                        Text(permissionLabel(permission, status: status))
                            .font(CampusStyle.body(12)).foregroundStyle(.secondary)
                    }
                    permissionIndicator(status, feature: permission)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(permission.title)
        .accessibilityValue(permissionLabel(permission, status: status))
        .accessibilityHint(status?.isGranted == true ? "앱 안에서 기능 사용 켜기 또는 끄기" : "iPhone 권한 허용 필요")
        .accessibilityIdentifier("my.settings.permission.\(permission)")
        .disabled(status == nil || permissionInFlight != nil)
    }

    private func permissionLabel(_ feature: MYPermission, status: PermissionStatus?) -> String {
        guard let status else { return "확인 중" }
        guard status.isGranted == true else { return status.label }
        return featureUsage.isEnabled(feature) ? "앱에서 사용 중" : "앱에서 사용 안 함"
    }

    private func completePendingPermission() {
        guard let feature = pendingPermissionToEnable, permissionValues[feature]?.isGranted == true else { return }
        featureUsage.setEnabled(true, for: feature)
        pendingPermissionToEnable = nil
    }

    private func permissionTitle(_ title: String) -> some View {
        Text(title).font(.custom("Paperlogy-3Light", size: 16, relativeTo: .body))
            .tracking(0.32).foregroundStyle(.black)
    }

    private func permissionIndicator(_ status: PermissionStatus?, feature: MYPermission) -> some View {
        ZStack {
            if let isGranted = status?.isGranted {
                let isOn = isGranted && featureUsage.isEnabled(feature)
                Capsule().fill(isOn ? CampusStyle.green : Color(uiColor: .tertiaryLabel))
                    .overlay(alignment: isOn ? .trailing : .leading) {
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
        var canRequest = false
    }

    @MainActor private func refreshPermissions() async {
        let location = locationStatus(locationPermission.status)
        let camera: PermissionStatus
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = .init(label: "허용됨", isGranted: true)
        case .denied, .restricted: camera = .init(label: "허용 안 함", isGranted: false)
        case .notDetermined: camera = .init(label: "요청 전", isGranted: false, canRequest: true)
        @unknown default: camera = .init(label: "확인 필요", isGranted: nil)
        }
        let photos: PermissionStatus
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized: photos = .init(label: "사진 추가 허용", isGranted: true)
        case .limited: photos = .init(label: "사진 추가 허용", isGranted: true)
        case .denied, .restricted: photos = .init(label: "허용 안 함", isGranted: false)
        case .notDetermined: photos = .init(label: "요청 전", isGranted: false, canRequest: true)
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
        case .notDetermined: permissionValues[.notifications] = .init(label: "요청 전", isGranted: false, canRequest: true)
        @unknown default: permissionValues[.notifications] = .init(label: "확인 필요", isGranted: nil)
        }
    }

    private func locationStatus(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedAlways: .init(label: "항상 허용", isGranted: true)
        case .authorizedWhenInUse: .init(label: "사용 중 허용", isGranted: true)
        case .notDetermined: .init(label: "요청 전", isGranted: false, canRequest: true)
        case .denied: .init(label: "허용 안 함", isGranted: false)
        case .restricted: .init(label: "기기에서 제한됨", isGranted: false)
        @unknown default: .init(label: "확인 필요", isGranted: nil)
        }
    }

    @MainActor private func changePermission(_ permission: MYPermission) async {
        guard permissionInFlight == nil else { return }
        permissionInFlight = permission
        defer { permissionInFlight = nil }
        await refreshPermissions()
        guard !Task.isCancelled, let status = permissionValues[permission] else { return }
        if status.isGranted == true {
            pendingPermissionToEnable = nil
            featureUsage.setEnabled(!featureUsage.isEnabled(permission), for: permission)
            return
        }
        pendingPermissionToEnable = permission
        guard status.canRequest else { openAppSettings(); return }
        if permission == .location {
            locationPermission.request()
            return // The retained delegate updates the displayed status.
        }
        switch permission {
        case .notifications:
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
            catch { if !Task.isCancelled { permissionError = error.localizedDescription } }
        case .camera: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .photos: _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        case .location: break
        }
        guard !Task.isCancelled else { return }
        await refreshPermissions()
        completePendingPermission()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { settingsError = true; return }
        openURL(url) { accepted in if !accepted { settingsError = true } }
    }
}

struct OiSettingsHeader: View {
    let title: String
    let back: () -> Void
    var close: (() -> Void)? = nil
    var backgroundColor: Color = .white
    var titleColor: Color = Color(red: 117 / 255, green: 75 / 255, blue: 0)

    var body: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: close == nil ? 19 : 22, weight: close == nil ? .semibold : .regular))
                    .frame(width: 50, height: 50, alignment: close == nil ? .center : .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(SettingsBackMaterial(isGlass: close == nil))
            .accessibilityLabel("이전 화면")
            Text(title)
                .font(.custom(close == nil ? "Paperlogy-7Bold" : "Paperlogy-6SemiBold", size: close == nil ? 30 : 26, relativeTo: .title))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 20))
                        .frame(width: 50, height: 50, alignment: .trailing).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("학교 자료 확인 닫기")
            } else {
                Color.clear.frame(width: 50, height: 50).accessibilityHidden(true)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 13)
        .background(backgroundColor)
    }
}

private struct SettingsBackMaterial: ViewModifier {
    let isGlass: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if isGlass { content.glassEffect(.regular.interactive(), in: Circle()) }
        else { content }
    }
}

private typealias MYPermission = OiAppFeature

#Preview("Settings · Reference", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack { MYSettingsView(remote: OiRemoteStore()) }
}

#Preview("Settings · Small", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack { MYSettingsView(remote: OiRemoteStore()) }
}

#Preview("Settings · Large", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack { MYSettingsView(remote: OiRemoteStore()) }
}

// Retain the permission delegate without starting a GPS tracking session.
@MainActor @Observable private final class MYLocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func request() { manager.requestWhenInUseAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.status = self.manager.authorizationStatus
        }
    }
}
