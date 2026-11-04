import SwiftUI

struct OiOperatorHomeView: View {
    let remote: OiRemoteStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var access = OiOperatorAccess()
    @State private var owner: UUID?
    @State private var path: [OiOperatorSection] = []
    @State private var retryID = UUID()

    private var canAccess: Bool {
        phase == .active && owner != nil && owner == remote.account?.id &&
        !remote.needsReauthentication && remote.isOperator && access.state == .allowed
    }

    private struct Context: Equatable {
        let owner: UUID?
        let active: Bool
        let needsAuthentication: Bool
        let retry: UUID
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if canAccess {
                    menu
                } else {
                    accessStatus
                }
            }
            .navigationTitle("운영자 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
            }
            .navigationDestination(for: OiOperatorSection.self) { section in
                if canAccess {
                    if section == .stories { OiOperatorStoriesView(remote: remote) }
                    else if section == .evidence { OiOperatorEvidenceListView(remote: remote) }
                    else { OiOperatorPendingView(section: section) }
                } else { accessStatus }
            }
        }
        .tint(CampusStyle.sectionGreen)
        .privacySensitive()
        .task(id: Context(owner: remote.account?.id, active: phase == .active,
                          needsAuthentication: remote.needsReauthentication, retry: retryID)) {
            access.invalidate()
            path = []
            owner = remote.account?.id
            guard owner != nil, phase == .active, !remote.needsReauthentication else { return }
            await access.check { try await remote.verifyOperatorAccess() }
            while !Task.isCancelled, phase == .active, access.state == .allowed {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await access.check { try await remote.verifyOperatorAccess() }
            }
        }
        .onChange(of: canAccess) { _, allowed in if !allowed { path = [] } }
        .onDisappear { access.invalidate(); path = [] }
    }

    private var menu: some View {
        List {
            Section {
                Text("증빙 검토와 이야기 공개를 관리합니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("검토 업무") {
                menuLink(.stories)
                menuLink(.evidence)
            }
            Section("운영 기록") { menuLink(.audit) }
            Section {
                Text("운영자의 작성 승인과 이야기 공개 승인은 학교의 공식 납입 확인·영수증 발급과 다릅니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("operator.home")
    }

    private func menuLink(_ section: OiOperatorSection) -> some View {
        NavigationLink(value: section) {
            Label {
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title).font(.headline)
                    Text(section.detail).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            } icon: { Image(systemName: section.symbol) }
        }.accessibilityIdentifier("operator.menu.\(section.rawValue)")
    }

    @ViewBuilder private var accessStatus: some View {
        if phase != .active || access.state == .checking && remote.account != nil && !remote.needsReauthentication {
            ProgressView("운영자 권한 확인 중")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("operator.access.loading")
        } else {
            ContentUnavailableView {
                Label(remote.account == nil || remote.needsReauthentication ? "로그인이 필요해요" :
                      access.state == .failed ? "권한을 확인하지 못했어요" : "운영자 권한이 필요해요",
                      systemImage: "lock.shield")
            } description: {
                Text(remote.account == nil || remote.needsReauthentication
                     ? "설정에서 다시 로그인한 뒤 이용해 주세요."
                     : access.state == .failed ? "연결 상태를 확인하고 다시 시도해 주세요."
                     : "이 계정으로는 운영자 관리 화면을 이용할 수 없어요.")
            } actions: {
                if remote.account != nil && !remote.needsReauthentication {
                    Button("다시 확인") { retryID = UUID() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("operator.access.retry")
                }
            }.accessibilityIdentifier("operator.access.unavailable")
        }
    }
}

enum OiOperatorSection: String, Hashable {
    case stories, evidence, audit
    var title: String {
        switch self { case .stories: "이야기 검토"; case .evidence: "기부 증빙 검토"; case .audit: "운영 감사 기록" }
    }
    var detail: String {
        switch self {
        case .stories: "이야기 내용 확인 및 공개·비공개 관리"
        case .evidence: "증빙 확인 및 작성 권한 검토"
        case .audit: "운영 처리 내역 확인"
        }
    }
    var symbol: String {
        switch self { case .stories: "text.book.closed"; case .evidence: "doc.text.magnifyingglass"; case .audit: "clock.arrow.circlepath" }
    }
}

private struct OiOperatorPendingView: View {
    let section: OiOperatorSection
    var body: some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.symbol)
        } description: {
            Text("이 관리 기능은 준비 중이에요. 현재 처리할 수 있는 목록은 제공하지 않습니다.")
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("operator.pending.\(section.rawValue)")
    }
}
