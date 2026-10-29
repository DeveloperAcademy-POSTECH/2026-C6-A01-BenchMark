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
                        Text("기존 벤치에 남긴 명패와 NFC로 기부자의 이야기를 이어가는 서비스예요.")
                        Button("전체 앱 보기", action: onRequestFullApp)
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            case .loading: ProgressView(viewModel.state.description)
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
            case .invalidLink: Text(viewModel.state.description)
            case .loadFailed: Text(viewModel.state.description)
            case .storyNotFound: Text(viewModel.state.description)
            case .arUnavailable: Text(viewModel.state.description)
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
