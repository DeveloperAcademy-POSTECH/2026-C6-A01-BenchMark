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



// 4. App Clip 화면 구성
/// 로딩 상태 화면 표시
/// 잘못된 링크 안내 화면 표시
/// 이야기 없음 안내 화면 표시
/// AR 사용 불가 시 Story 화면 표시
/// 준비 완료 시 임시 AR 화면 표시

// 최소 AR 기능 연결
/// 현재 기기의 AR 지원 여부 확인
/// 준비 완료 상태에서 실제 AR 화면 실행
/// AR 세션 시작과 종료 기능 재사용
/// 해당 명패에 맞는 캐릭터 하나만 표시
/// 영상 촬영, 캐릭터 선택, 복잡한 설정은 제외
/// App Clip에 포함되는 AR 에셋 용량 확인

// 5. AR 사진 촬영
/// AR 장면을 사진으로 촬영
/// 촬영 결과를 임시 파일로 생성
/// 촬영 결과 미리보기 표시
/// PhotoKit 직접 저장 기능은 App Clip에서 제외

// 6. AR 사진 공유
/// 촬영한 사진을 시스템 공유 시트에 전달
/// 공유 완료와 취소 처리
/// 사용이 끝난 임시 파일 정리
/// 실기기에서 사용할 수 있는 공유 항목 확인
