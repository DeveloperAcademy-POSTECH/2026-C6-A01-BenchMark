//
//  AppClipExperience.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import Foundation

// TODO: RewardCard 타입을 직접 작성한다.
// - 카드 식별자를 나타내는 값
// - Figma에서 확인한 "텍스트와 컴포넌트가 합쳐진 하나의 카드 이미지"를 불러올 값
// - 이 타입에는 Story의 제목이나 본문을 중복해서 저장하지 않는다.

struct RewardCard {
    let id: String /// 어떤 보상 카드인지 식별
    let imageURL: URL
}

// TODO: AppClipExperience 타입을 직접 작성한다.
// - 기존 공통 Story를 포함한다.
// - 위에서 작성한 RewardCard를 포함한다.
// - URL로 받은 storyID를 다시 별도 프로퍼티로 중복 저장할 필요가 있는지 확인한다.

struct AppClipExperience {
    let story: Story
    let rewardCard: RewardCard
}
