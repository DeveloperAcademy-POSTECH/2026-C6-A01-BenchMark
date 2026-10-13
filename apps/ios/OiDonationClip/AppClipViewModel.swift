//
//  AppClipViewModel.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import Foundation
import Observation


@Observable
@MainActor
final class AppClipViewModel {
    
    /// 3-1. StoryRepository를 따르는 실제 구현체를 저장
    private let storyRepository: any StoryRepository
    
    // 1. App Clip 상태 관리
    /// 1-1. 상태 종류 정의
    enum State {
        case loading
        case ready
        case invalidLink
        case loadFailed
        case storyNotFound
        case arUnavailable
        
        var description: String {
            switch self {
            case .loading: "로딩 중"
            case .ready: "준비 완료"
            case .invalidLink: "유효하지 않은 링크"
            case .loadFailed: "Story 불러오기를 실패하였습니다"
            case .storyNotFound: "스토리가 없습니다"
            case .arUnavailable: "AR을 사용할 수 없습니다"
            }
        }
    }
    
    /// 1-2. 현재 상태와 전달받은 값 저장
    private(set) var state: State = .loading /// 현재 상태 저장하는 프로퍼티 (값을 변경하는 set만 private으로 바꾸기)
    private(set) var invocationURL: URL?
    private(set) var plaqueID: String?
    private(set) var story: Story?
    
    // 2. App Clip URL 처리
    /// 2-1. 허용 도메인이 설정된 URL 파서를 외부에서 전달받아 보관
    private let linkParser: PublicLinkParser
    
    /// ViewModel 생성 시 전달받은 URL 파서를 내부 프로퍼티에 저장
    init(linkParser: PublicLinkParser, storyRepository: any StoryRepository) {
        self.linkParser = linkParser
        self.storyRepository = storyRepository
    }
    
    /// 2-2. NFC 또는 App Clip 호출 URL 수신
    func handleInvocationURL(invocationURL: URL?) async {
        if let invocationURL {
            self.invocationURL = invocationURL /// self.invocationURL: ViewModel이 보관하는 프로퍼티
            let destination = linkParser.parse(invocationURL)
            
            /// 2-3. PublicLinkParser의 검사 결과에 따라 plaqueID 저장 또는 오류 상태 변경
            /// Story URL이면 plaqueID 저장, Bench URL 또는 파싱 실패면 유효하지 않은 링크로 처리
            switch destination {
            case .bench(_): state = .invalidLink
            case .story(let id):
                plaqueID = id
                /// 3-6. 유효한 Story ID를 저장한 후 연결된 Story 조회
                await loadStory(plaqueID: id)
            case nil: state = .invalidLink
            }
            
            
        } else {
            state = .invalidLink
        }
    }
    
    /// 3-4. plaqueID로 연결된 Story를 비동기로 조회
    func loadStory(plaqueID: String) async {
        /// 3-5. 조회 결과에 따라 Story와 상태 변경
        story = nil
        state = .loading
        do  {
            if let fetchedStory = try await storyRepository.fetchPublicStory(plaqueID: plaqueID) {
                self.story = fetchedStory
                state = .ready
            } else {
                state = .storyNotFound
            }
        } catch {
            state = .loadFailed
        }
    }
}
