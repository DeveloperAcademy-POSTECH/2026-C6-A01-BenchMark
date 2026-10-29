import SwiftUI

/// Keeps the existing donation, camera and photo tools reachable from the redesigned home.
struct CampusProfileMenu: View {
    let container: AppContainer
    let store: CampusStoryStore
    let onCamera: () -> Void
    var remote: OiRemoteStore? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var information: HomeDestination?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("OiFarmer").resizable().scaledToFit().frame(width: 60, height: 80)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(remote == nil ? "신서임당" : remote?.profile?.nickname ?? "농부").font(.title2.bold())
                            Text(remote == nil ? "디자인 예시 프로필 · 이 기기에 수집 \(store.collected.count)개" : "계정에 저장한 오이 \(store.collected.count)개").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let remote {
                    Section("계정과 이야기") {
                        NavigationLink("로그인·프로필·기부 증빙·내 이야기") { OiAccountView(remote: remote) }
                    }
                }
                Section("수집한 오이") {
                    if store.collected.isEmpty { Text("캠퍼스의 오이를 눌러 이야기를 수집해 보세요.").foregroundStyle(.secondary) }
                    ForEach(store.stories.filter { store.collected.contains($0.id) }) { story in
                        NavigationLink(value: CampusDestination.story(story.id)) { Label(story.title, systemImage: "leaf.fill") }
                    }
                }
                Section(remote == nil ? "나의 참여" : "이전 파일럿 메뉴 · 미연동") {
                    NavigationLink {
                        MyDonationsView(repository: container.participationRepository, showDesignExamples: container.showsDesignExamples) { information = .donation }
                    } label: { Label("내 기부", systemImage: "heart.fill") }
                    NavigationLink {
                        SponsorshipView(benches: container.benchRepository, participation: container.participationRepository) { dismiss() }
                    } label: { Label("후원 · 참여 안내", systemImage: "hand.palm.facing.fill") }
                    NavigationLink { BenchesView(repository: container.benchRepository) } label: { Label("기존 벤치지도", systemImage: "map") }
                }
                Section("촬영") {
                    Button("AR 카메라", systemImage: "camera.fill") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onCamera() } }
                    NavigationLink { PhotoTestView() } label: { Label("사진 테스트", systemImage: "photo.on.rectangle") }
                    NavigationLink { NFCWriteView() } label: { Label("NFC", systemImage: "wave.3.right") }
                        .accessibilityHint("App Clip 링크를 NFC 태그에 기록하는 화면을 엽니다")
                }
                Section {
                    Text(remote == nil ? "지도 속 오이의 수, 이름, 사진과 기부 횟수는 Figma 디자인 예시입니다. 위치는 캠퍼스 모델에 배치한 예시이며 실제 기부나 현장 방문을 인증하지 않습니다." : "계정의 수집 기록, 운영자의 글 작성 승인과 학교 공식 기부 확인은 서로 다릅니다. 현장 방문 인증과 AR 수집 게임은 아직 준비 중입니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("내 오이").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .navigationDestination(for: CampusDestination.self) { destination in
                switch destination {
                case .summary(let id): if let story = store.story(id) { CampusSummaryView(story: story, store: store) }
                case .story(let id): if let story = store.story(id) { CampusStoryDetailView(story: story, store: store) }
                }
            }
            .navigationDestination(for: PublicLinkParser.Destination.self) {
                PublicDestinationView(destination: $0, benches: container.benchRepository, stories: container.storyRepository)
            }
            .sheet(item: $information) { HomeInformationSheet(destination: $0) }
        }
    }
}
