import SwiftUI

struct OiStoryListScreen: View {
    let remote: OiRemoteStore

    @State private var selectedStoryID: UUID?
    @State private var showingEditor = false
    @State private var showingApprovalNotice = false
    @State private var showingTicketNotice = false

    var body: some View {
        OiStoryListView(
            state: state,
            onRetry: { Task { await remote.refresh() } },
            onSelectStory: selectStory,
            onCreateStory: beginCreatingStory,
            onUseTicket: { showingTicketNotice = true }
        )
        .navigationDestination(item: $selectedStoryID) { storyID in
            OiStoryManagement(remote: remote, storyID: storyID)
        }
        .navigationDestination(isPresented: $showingEditor) {
            OiStoryEditor(remote: remote)
        }
        .alert("작성 승인이 필요해요", isPresented: $showingApprovalNotice) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("증빙 검토와 이야기 작성 승인을 받은 뒤 오이와 이야기를 만들 수 있어요.")
        }
        .alert("티켓 기능은 준비 중이에요", isPresented: $showingTicketNotice) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("티켓 보유량과 사용 규칙이 확정되면 이 버튼에 연결할 예정이에요.")
        }
    }

    private var state: OiStoryListState {
        if let error = remote.loadError, remote.ownStories.isEmpty {
            return .failure(error)
        }
        guard remote.hasLoadedRemote else { return .loading }
        guard !remote.ownStories.isEmpty else { return .empty }

        let donorName = remote.profile?.nickname.nonEmpty ?? "익명"
        return .content(remote.ownStories.map { story in
            OiStoryListItem(
                story: story,
                donorDisplayName: donorName,
                locationDisplayName: locationDisplayName(for: story.regionId)
            )
        })
    }

    private func selectStory(id: UUID) {
        guard remote.ownStories.contains(where: { $0.id == id }) else { return }
        selectedStoryID = id
    }

    private func beginCreatingStory() {
        if remote.grants.contains(where: { $0.revokedAt == nil }) {
            showingEditor = true
        } else {
            showingApprovalNotice = true
        }
    }

    private func locationDisplayName(for regionID: String) -> String {
        guard let region = CampusRegion.examples.first(where: { $0.id == regionID }) else {
            return "포항공과대학교"
        }
        return "포항공과대학교 \(region.title)"
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
