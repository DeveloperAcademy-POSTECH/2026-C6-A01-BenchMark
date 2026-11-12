//
//  ContentView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import SwiftUI

struct AppClipInvocation: Hashable {
    let id = UUID()
    let url: URL?
}

struct AppClipExperienceView<SafetyButton: View>: View {
    private let invocation: AppClipInvocation?
    private let onRequestFullApp: (() -> Void)?
    private let onOpenPostcardPrototype: (() -> Void)?
    private let storySafetyButton: (Story, UUID) -> SafetyButton

    @State private var viewModel: AppClipViewModel
    @State private var selection: AppClipInvocation?
    @State private var isPlaying = false
    @State private var showingBlocked = false
    @Environment(\.scenePhase) private var phase
    @State private var showingSupport = false
    @State private var showingSample = false

    init(
        storyRepository: any StoryRepository,
        invocation: AppClipInvocation? = nil,
        onRequestFullApp: (() -> Void)? = nil,
        onOpenPostcardPrototype: (() -> Void)? = nil,
        @ViewBuilder storySafetyButton: @escaping (Story, UUID) -> SafetyButton
    ) {
        self.invocation = invocation
        self.onRequestFullApp = onRequestFullApp
        self.onOpenPostcardPrototype = onOpenPostcardPrototype
        self.storySafetyButton = storySafetyButton
        _selection = State(initialValue: invocation)
        _viewModel = State(initialValue: AppClipViewModel(storyRepository: storyRepository))
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
                    Section {
                        Button("이야기·AR 체험") { showingSample = true }
                            .frame(minHeight: 44).accessibilityIdentifier("appclip.sample")
                        Text("기부나 로그인 없이 예시 이야기를 읽고 AR을 체험해 보세요. 실제 도감에는 저장되지 않아요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let onOpenPostcardPrototype {
                        Section("개발용") {
                            Button("AR 엽서 퍼즐 테스트", action: onOpenPostcardPrototype)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("appclip.postcardPrototype")
                        }
                    }
                    Section("공개 이야기") {
                        ForEach(visibleStories) { story in
                            Button {
                                selection = AppClipInvocation(url: AppClipLink.storyURL(story.id))
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
                    if let onRequestFullApp {
                        Button("전체 앱 보기", action: onRequestFullApp).frame(minHeight: 44)
                    }
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
                                if let id = UUID(uuidString: experience.story.storyID) {
                                    storySafetyButton(experience.story, id)
                                }
                                Button("AR에서 오이 찾기") { isPlaying = true }
                                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                                    .accessibilityIdentifier("appclip.story.ar")
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
                        Button("다시 시도") { selection = AppClipInvocation(url: url) }
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
        .fullScreenCover(isPresented: $showingSample) { OiSampleExperienceView() }
        .sheet(isPresented: $showingBlocked) { OiBlockedAuthorsView() }
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in
            if let story = viewModel.story, OiContentSafetyStore.shared.isBlocked(story.donorID) {
                isPlaying = false; viewModel.showWelcome()
            }
        }
        .onChange(of: phase) { _, phase in if phase == .active { OiContentSafetyStore.shared.reload() } }
        .task(id: viewModel.state) {
            if viewModel.state == .welcome { await viewModel.loadPublicStories(reset: true) }
        }
        .onChange(of: invocation) { _, invocation in selection = invocation }
        .onChange(of: selection?.id) { _, _ in isPlaying = false; showingSample = false }
        .onChange(of: viewModel.state) { _, state in if state != .ready { isPlaying = false } }
        .task(id: selection?.id) {
            guard let selection else { return }
            await viewModel.handleInvocationURL(invocationURL: selection.url)
        }
    }
}
