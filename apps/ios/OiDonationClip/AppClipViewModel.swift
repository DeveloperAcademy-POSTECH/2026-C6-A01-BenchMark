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
    private let storyRepository: any StoryRepository
    private let linkParser: PublicLinkParser?
    private var invocationID = UUID()

    enum State: Equatable {
        case welcome
        case loading
        case ready
        case invalidLink
        case loadFailed
        case storyNotFound
        case arUnavailable
        
        var description: String {
            switch self {
            case .welcome: "오래 남는 이야기 기부"
            case .loading: "이야기를 불러오는 중이에요"
            case .ready: "AR을 시작할 준비가 되었어요"
            case .invalidLink: "올바르지 않은 링크예요. 명패의 NFC를 다시 인식해 주세요"
            case .loadFailed: "이야기를 불러오지 못했어요. 잠시 후 다시 시도해 주세요"
            case .storyNotFound: "이 명패에 연결된 이야기를 찾을 수 없어요"
            case .arUnavailable: "이 기기에서는 AR을 사용할 수 없어요. 대신 이야기를 확인해 주세요"
            }
        }
    }
    private(set) var state: State = .welcome
    private(set) var invocationURL: URL?
    private(set) var storyID: String?
    private(set) var story: Story?
    init(linkParser: PublicLinkParser? = nil, storyRepository: any StoryRepository) {
        self.linkParser = linkParser
        self.storyRepository = storyRepository
    }
    func handleInvocationURL(invocationURL: URL?) async {
        guard !Task.isCancelled else { return }
        let currentInvocation = UUID()
        invocationID = currentInvocation
        self.invocationURL = invocationURL
        storyID = nil
        story = nil

        guard let invocationURL else {
            state = .invalidLink
            return
        }
        if AppClipLink.matches(invocationURL) {
            state = .welcome
            return
        }
        guard case .story(let id) = linkParser?.parse(invocationURL) else {
            state = .invalidLink
            return
        }

        storyID = id
        state = .loading
        do {
            let fetchedStory = try await storyRepository.fetchPublicStory(storyID: id)
            guard invocationID == currentInvocation, !Task.isCancelled else { return }
            if let fetchedStory {
                self.story = fetchedStory
                state = .ready
            } else {
                state = .storyNotFound
            }
        } catch is CancellationError {
            return
        } catch {
            guard invocationID == currentInvocation, !Task.isCancelled else { return }
            state = .loadFailed
        }
    }

    func showWelcome() {
        invocationID = UUID()
        invocationURL = nil
        storyID = nil
        story = nil
        state = .welcome
    }
}
