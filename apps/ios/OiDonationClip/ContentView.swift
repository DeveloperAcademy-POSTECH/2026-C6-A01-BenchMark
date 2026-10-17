//
//  ContentView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import SwiftUI

struct ContentView: View {
    
    @State private var viewModel: AppClipViewModel
    
    /// 3-3. 전달받은 URL 파서와 StoryRepository로 ViewModel 생성
    init(linkParser: PublicLinkParser, storyRepository: any StoryRepository) {
        _viewModel = State(initialValue: AppClipViewModel(linkParser: linkParser, storyRepository: storyRepository))
    }
    
    var body: some View {
        
        
        Group {
            /// 1-3. 현재 상태에 따라 화면이 변경되도록 관리
            switch viewModel.state {
            case .loading: ProgressView(viewModel.state.description)
            case .ready: Text(viewModel.state.description)
            case .invalidLink: Text(viewModel.state.description)
            case .loadFailed: Text(viewModel.state.description)
            case .storyNotFound: Text(viewModel.state.description)
            case .arUnavailable: Text(viewModel.state.description)
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            Task {
                /// 2-4. App Clip 실행 URL을 수신하여 ViewModel에 전달
                await viewModel.handleInvocationURL(invocationURL: userActivity.webpageURL)
            }
        }
    }
    
}

#Preview {
    ContentView(
        linkParser: PublicLinkParser(allowedHost: "example.com"), storyRepository: TestStoryRepository()
    )
}
