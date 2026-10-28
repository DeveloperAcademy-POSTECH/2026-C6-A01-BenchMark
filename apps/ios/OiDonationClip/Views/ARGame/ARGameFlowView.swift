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
    let story: Story
    let onBack: () -> Void

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
            case .intro:
                ARGameIntroView(
                    cucumberName: story.title,
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
            case .playing:
                ZStack(alignment: .topLeading) {
                    ARGameCameraView()
                        .ignoresSafeArea()

                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .padding()
                    .accessibilityLabel("AR 게임 나가기")
                }
            case .permissionDenied:
                statePanel(
                    title: "카메라 권한이 필요해요",
                    message: "설정에서 오이기부의 카메라 접근을 허용해 주세요.",
                    buttonTitle: "돌아가기",
                    action: onBack
                )
            case .success:
                statePanel(title: "수집 성공", buttonTitle: "처음으로") {
                    viewModel.reset()
                }
            case .failure:
                statePanel(title: "수집 실패", buttonTitle: "다시 시도") {
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
        .buttonStyle(.borderedProminent)
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
        }
        .padding()
    }
}
