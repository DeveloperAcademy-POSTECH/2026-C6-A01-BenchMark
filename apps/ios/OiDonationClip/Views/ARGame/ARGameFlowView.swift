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
    let onRequestFullApp: (() -> Void)?
    var validateCollection: (() async -> Bool)? = nil
    @State private var validating = false
    @State private var validationError: String?
    @State private var saveTask: Task<Void, Never>?

    @State private var collectionStore = StoryCollectionStore()

    var body: some View {
        ARCollectionGameView(
            cucumberName: experience.story.cucumberName,
            cucumberImageURL: experience.story.cucumberImageURL,
            onBack: onBack
        ) { retry in
            let persistenceError = collectionStore.persistenceError
            AppClipStoryCardView(
                experience: experience,
                isCollected: collectionStore.contains(storyID: experience.story.storyID),
                cancelTitle: persistenceError == nil ? "삭제" : "닫기",
                notice: validationError ?? persistenceError,
                onCollect: {
                    guard !validating else { return }
                    validating = true; validationError = nil
                    saveTask = Task {
                        defer { validating = false }
                        if let validateCollection, !(await validateCollection()) {
                            guard !Task.isCancelled else { return }
                            validationError = "이야기의 공개 상태를 확인하지 못했어요. 목록으로 돌아가 다시 확인해 주세요."
                            return
                        }
                        guard !Task.isCancelled else { return }
                        let saved = collectionStore.collect(experience.storyCard)
                        guard collectionStore.persistenceError == nil,
                              saved || collectionStore.contains(storyID: experience.story.storyID) else { return }
                        onRequestFullApp?()
                    }
                },
                onCancel: {
                    saveTask?.cancel()
                    if persistenceError != nil {
                        onBack()
                        return
                    }
                    guard collectionStore.remove(storyID: experience.story.storyID) else { return }
                    retry()
                }
            )
            .disabled(validating)
        }
        .onDisappear { saveTask?.cancel(); saveTask = nil }
    }
}

/// The camera, timer and round lifecycle are shared by the full app and App Clip.
/// Each caller owns the explicit post-win save action and its persistence contract.
struct ARCollectionGameView<SuccessContent: View>: View {
    let cucumberName: String
    var cucumberImageURL: URL? = nil
    var cucumberAssetName: String? = nil
    let onBack: () -> Void
    @ViewBuilder let successContent: (@escaping () -> Void) -> SuccessContent

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReturningFromSettings = false
    @State private var introTransitionDuration: Double? = 0.4

    @State private var viewModel = ARGameViewModel(
        isARSupported: {
            ARWorldTrackingConfiguration.isSupported
        },
        requestCameraAccess: {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                true
            case .notDetermined:
                await AVCaptureDevice.requestAccess(for: .video)
            case .denied, .restricted:
                false
            @unknown default:
                false
            }
        }
    )

    var body: some View {
        ZStack {
            if usesDarkStage {
                Color.black.ignoresSafeArea().transition(.identity)
            }
            switch viewModel.state {
            case .introBackground, .intro:
                ARGameIntroView(
                    cucumberName: cucumberName,
                    cucumberImageURL: cucumberImageURL,
                    cucumberAssetName: cucumberAssetName,
                    showsControls: viewModel.state == .intro,
                    targetCount: 3,
                    timeLimitSeconds: 30,
                    onBack: onBack
                ) {
                    viewModel.requestPermission()
                }
                .task(id: viewModel.state) {
                    guard viewModel.state == .introBackground else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    viewModel.showIntro()
                }
                .transition(.opacity)
            case .requestingPermission:
                ProgressView()
                    .accessibilityLabel("카메라 권한을 확인하고 있어요")
                    .task {
                        await viewModel.resolvePermission()
                    }
            case .starting, .playing:
                ARGamePlayingView(
                    viewModel: viewModel,
                    cucumberImageURL: cucumberImageURL,
                    cucumberAssetName: cucumberAssetName
                )
                // The incoming stage fades in, but removing it tears down the camera immediately.
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            case .permissionDenied:
                VStack(spacing: 16) {
                    statePanel(
                        title: "카메라 권한이 필요해요",
                        message: "설정에서 오이기부의 카메라 접근을 허용해 주세요.",
                        buttonTitle: "돌아가기",
                        action: onBack
                    )
                    Button("설정 열기") {
                        guard let settings = URL(string: UIApplication.openSettingsURLString) else { return }
                        isReturningFromSettings = true
                        openURL(settings) { accepted in
                            if !accepted { isReturningFromSettings = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .success:
                ARGameSuccessView(onFinished: viewModel.showStoryCard)
                    .transition(.opacity)
            case .storyCard:
                successContent { resetRound() }
                    .transition(.opacity)
            case .failure:
                ARGameFailureView {
                    guard viewModel.state == .failure else { return }
                    resetRound(introDuration: 0.2)
                }
                .transition(.opacity)
            case .unavailable:
                statePanel(
                    title: "AR을 사용할 수 없어요",
                    message: "AR을 지원하는 iPhone에서 다시 시도해 주세요.",
                    buttonTitle: "돌아가기",
                    action: onBack
                )
            case .cameraUnavailable:
                statePanel(
                    title: "카메라가 중단되었어요",
                    message: "주변을 비추며 다시 시작해 주세요.",
                    buttonTitle: "다시 시작",
                    action: { resetRound() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(stageAnimation, value: viewModel.state)
        .overlay(alignment: .topLeading) {
            if viewModel.state != .intro && viewModel.state != .introBackground && viewModel.state != .storyCard {
                Button(action: onBack) {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("수집 게임 닫기")
                .padding(.leading, 20)
                .padding(.top, 8)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isReturningFromSettings else { return }
            isReturningFromSettings = false
            viewModel.retryPermission()
        }
    }

    private var usesDarkStage: Bool {
        switch viewModel.state {
        case .starting, .playing, .success, .failure: true
        default: false
        }
    }

    private var stageAnimation: Animation? {
        guard !reduceMotion else { return nil }
        // Figma prototype reactions in the collection AR section (2876:8317).
        let duration: Double?
        switch viewModel.state {
        case .intro: duration = introTransitionDuration
        case .starting, .failure: duration = 0.2
        case .success: duration = 0.1
        case .storyCard: duration = 0.3
        default: duration = nil
        }
        return duration.map { .timingCurve(0, 0, 0.58, 1, duration: $0) }
    }

    private func resetRound(introDuration: Double? = nil) {
        introTransitionDuration = introDuration
        viewModel.reset()
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
