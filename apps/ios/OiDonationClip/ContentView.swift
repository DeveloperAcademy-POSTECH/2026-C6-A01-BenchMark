//
//  ContentView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import SwiftUI

struct ContentView: View {
    let onRequestFullApp: () -> Void

    @State private var viewModel: AppClipViewModel
    @State private var invocation: Invocation?
    @State private var isPlaying = false
    @State private var showingSafety = false
    @State private var showingBlocked = false
    @Environment(\.scenePhase) private var phase
    @State private var showingSupport = false

    private struct Invocation {
        let id = UUID()
        let url: URL?
    }
    
    /// 3-3. 전달받은 URL 파서와 StoryRepository로 ViewModel 생성
    init(
        linkParser: PublicLinkParser? = nil,
        storyRepository: any StoryRepository,
        onRequestFullApp: @escaping () -> Void = {}
    ) {
        self.onRequestFullApp = onRequestFullApp
        _viewModel = State(initialValue: AppClipViewModel(linkParser: linkParser, storyRepository: storyRepository))
    }
    
    private var visibleStories: [PublicStorySummary] {
        viewModel.publicStories.filter { !OiContentSafetyStore.shared.isBlocked($0.userId) }
    }

    var body: some View {
        
        Group {
            /// 1-3. 현재 상태에 따라 화면이 변경되도록 관리
            switch viewModel.state {
            case .welcome:
                List {
                    Section {
                        Text("오이기부").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("공개 이야기를 읽고 AR에서 오이 카드를 모아 보세요.")
                    }
                    Section("공개 이야기") {
                        ForEach(visibleStories) { story in
                            Button {
                                invocation = Invocation(url: AppClipLink.storyURL(story.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(story.cucumberName).font(.headline)
                                    Text(story.title).font(.subheadline).foregroundStyle(.secondary)
                                }.frame(minHeight: 44)
                            }
                        }
                        if viewModel.isLoadingStories { ProgressView("이야기 불러오는 중") }
                        else if let error = viewModel.listError {
                            Text(error)
                            Button("다시 시도") { Task { await viewModel.loadPublicStories(reset: true) } }
                        } else if visibleStories.isEmpty {
                            Text("표시할 공개 이야기가 없어요. 새로고침하거나 차단한 작성자 목록을 확인해 주세요.")
                            Button("새로고침") { Task { await viewModel.loadPublicStories(reset: true) } }
                        }
                        if !viewModel.isLoadingStories && viewModel.hasMoreStories {
                            Button("더 보기") { Task { await viewModel.loadPublicStories() } }
                        }
                    }
                    Button("전체 앱 보기", action: onRequestFullApp).frame(minHeight: 44)
                }
                .refreshable { await viewModel.loadPublicStories(reset: true) }
            case .loading:
                ProgressView()
                    .accessibilityLabel(viewModel.state.description)
            case .ready:
                if let experience = viewModel.experience {
                    if isPlaying {
                        ARGameFlowView(
                            experience: experience,
                            onBack: { isPlaying = false },
                            onRequestFullApp: onRequestFullApp,
                            validateCollection: { await viewModel.canCollectCurrentStory() }
                        )
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Button("이야기 목록") { viewModel.showWelcome() }
                                Text(experience.story.title).font(.title.bold())
                                Text(experience.story.donorDisplayName + " · " + experience.story.location.displayName)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(experience.story.content).textSelection(.enabled)
                                Button("신고 및 차단") { showingSafety = true }
                                Button("AR에서 오이 찾기") { isPlaying = true }
                                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                                Text("카메라를 사용해 오이 3개를 찾으면 카드를 이 기기에 보관할 수 있어요. 기부·방문 인증이나 작성 승인이 아닙니다.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                    }
                } else {
                    Text(viewModel.state.description)
                }
            case .invalidLink, .loadFailed, .storyNotFound, .arUnavailable:
                VStack(spacing: 16) {
                    Text(viewModel.state.description).multilineTextAlignment(.center)
                    if viewModel.state == .loadFailed, let url = viewModel.invocationURL {
                        Button("다시 시도") { invocation = Invocation(url: url) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("처음으로") { viewModel.showWelcome() }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("개인정보 및 지원") { showingSupport = true }.frame(maxWidth: .infinity, minHeight: 44)
                Button("차단한 작성자") { showingBlocked = true }.frame(maxWidth: .infinity, minHeight: 44)
            }.font(.footnote).background(.regularMaterial)
        }
        .sheet(isPresented: $showingSupport) { OiSupportView() }
        .sheet(isPresented: $showingBlocked) { OiBlockedAuthorsView() }
        .sheet(isPresented: $showingSafety) {
            if let story = viewModel.story, let id = UUID(uuidString: story.storyID) {
                OiContentSafetyView(storyID: id, authorID: story.donorID, authorName: story.donorDisplayName,
                    onBlock: { isPlaying = false; viewModel.showWelcome() })
            }
        }
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in
            if let story = viewModel.story, OiContentSafetyStore.shared.isBlocked(story.donorID) {
                isPlaying = false; viewModel.showWelcome()
            }
        }
        .onChange(of: phase) { _, phase in if phase == .active { OiContentSafetyStore.shared.reload() } }
        .task(id: viewModel.state) {
            if viewModel.state == .welcome { await viewModel.loadPublicStories(reset: true) }
        }
        .onChange(of: invocation?.id) { _, _ in isPlaying = false }
        .onChange(of: viewModel.state) { _, state in if state != .ready { isPlaying = false } }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            invocation = Invocation(url: userActivity.webpageURL)
        }
        .onOpenURL { url in
            invocation = Invocation(url: url)
        }
        .task(id: invocation?.id) {
            guard let invocation else { return }
            await viewModel.handleInvocationURL(invocationURL: invocation.url)
        }
    }

}

#Preview {
    ContentView(storyRepository: RealStoryRepository())
}
