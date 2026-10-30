//
//  ARGameFlowView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import ARKit
import AVFoundation
import SwiftUI

struct ARGameFlowView: View {
    let experience: AppClipExperience
    let onBack: () -> Void
    let onRequestFullApp: () -> Void

    private var story: Story { experience.story }

    @State private var collectionStore = StoryCollectionStore()

    @State private var viewModel = ARGameViewModel(
        isARSupported: {
            ARWorldTrackingConfiguration.isSupported
        },
        requestCameraAccess: {
            await AVCaptureDevice.requestAccess(for: .video)
        }
    )

    var body: some View {
        Group {
            switch viewModel.state {
            case .introBackground:
                Image("ARGameIntroBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .task {
                        do {
                            try await Task.sleep(for: .milliseconds(300))
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        viewModel.showIntro()
                    }
            case .intro:
                ARGameIntroView(
                    cucumberName: story.title,
                    cucumberImageURL: story.cucumberImageURL,
                    targetCount: 3,
                    timeLimitSeconds: 30,
                    onBack: onBack
                ) {
                    viewModel.requestPermission()
                }
            case .requestingPermission:
                ProgressView("카메라 권한을 확인하고 있어요")
                    .task {
                        await viewModel.resolvePermission()
                    }
            case .starting:
                ZStack {
                    Color.black.opacity(0.95)
                        .ignoresSafeArea()
                    Text("시작!")
                        .font(.custom("PearToucan-Regular", size: 60, relativeTo: .largeTitle).weight(.bold))
                        .foregroundStyle(.white)
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(700))
                    viewModel.beginPlaying()
                }
            case .playing:
                ARGamePlayingView(
                    viewModel: viewModel,
                    cucumberImageURL: story.cucumberImageURL
                )
            case .permissionDenied:
                statePanel(
                    title: "카메라 권한이 필요해요",
                    message: "설정에서 오이기부의 카메라 접근을 허용해 주세요.",
                    buttonTitle: "돌아가기",
                    action: onBack
                )
            case .success:
                ARGameSuccessView {
                    viewModel.showStoryCard()
                }
            case .storyCard:
                AppClipStoryCardView(
                    experience: experience,
                    isCollected: collectionStore.contains(storyID: story.storyID),
                    onCollect: {
                        collectionStore.collect(experience.storyCard)
                        onRequestFullApp()
                    },
                    onCancel: { viewModel.reset() }
                )
            case .failure:
                ARGameFailureView {
                    viewModel.reset()
                }
            case .unavailable:
                statePanel(
                    title: "AR을 사용할 수 없어요",
                    message: "AR을 지원하는 iPhone에서 다시 시도해 주세요.",
                    buttonTitle: "돌아가기",
                    action: onBack
                )
            }
        }
    }

    private func statePanel(
        title: String,
        message: String? = nil,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2)
            if let message {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
