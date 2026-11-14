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
                    else if section == .content { OiOperatorContentView(remote: remote) }
                    else if section == .nfcTags { OiOperatorNFCTagsView(remote: remote) }
                    else { OiOperatorAuditView(remote: remote) }
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
                Text("공개 요청과 콘텐츠 신고를 관리합니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("검토 업무") {
                menuLink(.content)
                menuLink(.stories)
            }
            Section("NFC 엽서") { menuLink(.nfcTags) }
            Section("운영 기록") { menuLink(.audit) }
            Section {
                Text("검토에서 승인한 이야기는 다른 사람의 지도와 AR에 공개됩니다.")
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
    case stories, audit, content, nfcTags
    var title: String {
        switch self {
        case .content: "콘텐츠 신고"; case .stories: "이야기 검토"; case .audit: "운영 감사 기록"; case .nfcTags: "NFC 태그"
        }
    }
    var detail: String {
        switch self {
        case .content: "신고 검토·게시물 비공개·작성자 제한"
        case .stories: "이야기 내용 확인 및 공개·비공개 관리"
        case .audit: "운영 처리 내역 확인"
        case .nfcTags: "캠퍼스 태그와 공개 이야기 연결·중지"
        }
    }
    var symbol: String {
        switch self {
        case .content: "flag"; case .stories: "text.book.closed"; case .audit: "clock.arrow.circlepath"
        case .nfcTags: "wave.3.right.circle"
        }
    }
}
