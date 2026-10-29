//
//  StoryRepository.swift
//  OiDonation
//
//  Created by jiwon hong on 10/13/26.
//

import Foundation

/// storyID로 Story를 찾아야 한다는 규칙
protocol StoryRepository: Sendable {
    func fetchPublicStory(storyID: String) async throws -> Story?
    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard?
}

/// 3-2. 테스트용 StoryRepository 작성
final class TestStoryRepository: StoryRepository {
    func fetchPublicStory(storyID: String) async throws -> Story? {
        
        guard storyID == "preview-story" else {
            return nil
        }
        
        let title = "오래도록 남는 이야기"
        let content = "App Clip 테스트용 이야기입니다. 어쩌구저쩌구 ~ 우리 벤치마크 팀 파이팅! 도라 하워드 모두 파이팅! 아카데미 파이팅!!"
        let donorID = UUID()
        
        return Story(
            storyID: storyID,
            donorID: donorID,
            donorDisplayName: "26학번 디벨로퍼학과 신서연",
            title: title,
            content: content,
            publishedAt: Date(timeIntervalSince1970: 1_792_724_400),
            location: StoryLocation(locationID: "preview-location", displayName: "POSTECH 지곡회관 옆 연못길"),
            tags: ["즐거움", "우정"],
            cucumberID: "preview-cucumber",
            cucumberName: "화성갈끄니까오이"
        )

    }

    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        guard storyID == "preview-story" else {
            return nil
        }

        let imageURL = Bundle.main.url(forResource: "AppClipStoryCardPreview", withExtension: "png")
            ?? URL(fileURLWithPath: "/AppClipStoryCardPreview.png")
        return StoryCard(cardID: "preview-card", storyID: storyID, imageURL: imageURL)
    }
}


final class RealStoryRepository: StoryRepository {
    func fetchPublicStory(storyID: String) async throws -> Story? {
        // 서버에 storyID를 넘겨서 받아온 Story 반환
        return nil
    }

    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        // 서버에 storyID를 넘겨서 받아온 StoryCard 반환
        return nil
    }
}

