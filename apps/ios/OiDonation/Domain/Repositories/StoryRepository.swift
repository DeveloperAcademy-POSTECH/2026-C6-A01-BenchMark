//
//  StoryRepository.swift
//  OiDonation
//
//  Created by jiwon hong on 10/13/26.
//

import Foundation

/// plaqueID로 Story를 찾아야 한다는 규칙
protocol StoryRepository: Sendable {
    func fetchPublicStory(plaqueID: String) async throws -> Story?
}

/// 3-2. 테스트용 StoryRepository 작성
class TestStoryRepository: StoryRepository {
    func fetchPublicStory(plaqueID: String) async throws -> Story? {
        
        guard plaqueID == "preview-plaque" else {
            return nil
        }
        
        let title = "오래도록 남는 이야기"
        let content = "App Clip 테스트용 이야기입니다. 어쩌구저쩌구 ~ 우리 벤치마크 팀 파이팅! 도라 하워드 모두 파이팅! 아카데미 파이팅!!"
        let donorID = UUID()
        
        return Story(plaqueID: plaqueID, donorID: donorID, title: title, content: content)

    }
}


class RealStoryRepository: StoryRepository {
    func fetchPublicStory(plaqueID: String) async throws -> Story? {
        // 서버에 plaqueID를 넘겨서 받아온 Story 반환
        return nil
    }
}

