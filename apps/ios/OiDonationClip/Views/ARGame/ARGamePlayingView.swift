// Created by 이돈혁

import SwiftUI

// Both states occupy this single branch of ARGameFlowView's switch.
struct ARGamePlayingView: View {
    let viewModel: ARGameViewModel
    let cucumberImageURL: URL?
    var cucumberAssetName: String? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraController: ARGameCameraController?

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                if let cameraController {
                    ARGameCameraView(controller: cameraController, isCollecting: viewModel.state == .playing)
                }

                ARGameHUD(
                    remainingSeconds: viewModel.remainingSeconds,
                    collectedCount: viewModel.collectedCount,
                    targetCount: viewModel.targetCount,
                    cucumberImageURL: cucumberImageURL,
                    cucumberAssetName: cucumberAssetName
                )

                if viewModel.state == .starting {
                    if cameraController?.isReady == true {
                        ARGameStartOverlay(onFinished: viewModel.finishStartAnimation)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .foregroundStyle(.white)
                            .accessibilityLabel("카메라를 준비하고 있어요")
                    }
                }
            }
        }
        .ignoresSafeArea()
        .task {
            // Lazy creation avoids constructing discarded ARViews on body updates.
            guard cameraController == nil else { return }
            let model = viewModel
            cameraController = ARGameCameraController(
                targetCount: viewModel.targetCount,
                cucumberImageURL: cucumberImageURL,
                cucumberAssetName: cucumberAssetName,
                onUnavailable: { [weak model] in model?.cameraBecameUnavailable() },
                onCollect: { [weak model] in model?.collectCucumber() }
            )
        }
        .task(id: viewModel.state) {
            // A stable view identity must still start a new task on entering playing.
            if viewModel.state == .playing { await viewModel.runTimer() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.cameraBecameUnavailable() }
        }
    }

}
