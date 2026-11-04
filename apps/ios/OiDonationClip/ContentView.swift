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
    
    var body: some View {
        
        Group {
            /// 1-3. 현재 상태에 따라 화면이 변경되도록 관리
            switch viewModel.state {
            case .welcome:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("오이기부").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text(viewModel.state.description).font(.title2)
                        Text("캠퍼스의 오이를 찾아 수집하고, 그곳에 남겨진 이야기를 만나 보세요.")
                        Button("전체 앱 보기", action: onRequestFullApp)
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            case .loading:
                ProgressView()
                    .accessibilityLabel(viewModel.state.description)
            case .ready:
                if let experience = viewModel.experience {
                    ARGameFlowView(
                        experience: experience,
                        onBack: { viewModel.showWelcome() },
                        onRequestFullApp: onRequestFullApp
                    )
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
