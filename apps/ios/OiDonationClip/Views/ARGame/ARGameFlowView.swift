//
//  ARGameFlowView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGameFlowView: View {
    let story: Story
    let onBack: () -> Void

    @State private var viewModel = ARGameViewModel()

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
                VStack(spacing: 20) {
                    Text("카메라 권한 확인")
                    HStack {
                        Button("허용") {
                            viewModel.permissionGranted()
                        }
                        Button("거절") {
                            viewModel.permissionDenied()
                        }
                    }
                }
            case .playing:
                VStack(spacing: 20) {
                    Text("AR 게임 진행 중")
                    HStack {
                        Button("성공") {
                            viewModel.finishGame(succeeded: true)
                        }
                        Button("실패") {
                            viewModel.finishGame(succeeded: false)
                        }
                    }
                }
            case .success:
                statePanel(title: "수집 성공", buttonTitle: "처음으로") {
                    viewModel.reset()
                }
            case .failure:
                statePanel(title: "수집 실패", buttonTitle: "다시 시도") {
                    viewModel.reset()
                }
            case .unavailable:
                statePanel(title: "AR을 사용할 수 없어요", buttonTitle: "돌아가기") {
                    viewModel.reset()
                }
            }
        }
        .buttonStyle(.borderedProminent)
    }

    private func statePanel(
        title: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2)
            Button(buttonTitle, action: action)
        }
    }
}
