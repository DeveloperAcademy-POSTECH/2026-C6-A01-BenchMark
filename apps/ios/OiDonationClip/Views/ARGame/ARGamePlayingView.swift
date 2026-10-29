//
//  ARGamePlayingView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGamePlayingView: View {
    let viewModel: ARGameViewModel
    let cucumberImageURL: URL?
    let onBack: () -> Void
    @State private var cameraController: ARGameCameraController

    init(
        viewModel: ARGameViewModel,
        cucumberImageURL: URL?,
        onBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.cucumberImageURL = cucumberImageURL
        self.onBack = onBack
        _cameraController = State(
            initialValue: ARGameCameraController(
                targetCount: viewModel.targetCount,
                cucumberImageURL: cucumberImageURL
            ) { [weak viewModel] in
                viewModel?.collectCucumber()
            }
        )
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ARGameCameraView(controller: cameraController)
                    .ignoresSafeArea()

                VStack {
                    timer
                        .padding(.top, 8)

                    Spacer()

                    collectionTray
                        .padding(.horizontal, 27)
                        .padding(.bottom, 2)
                }

                VStack {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("AR 게임 나가기")

                        Spacer()
                    }
                    .padding()

                    Spacer()
                }
            }
        }
        .task {
            await viewModel.runTimer()
        }
    }

    private var timer: some View {
        HStack(spacing: 13) {
            Image(systemName: "clock.fill")
            Text("\(viewModel.remainingSeconds)")
                .font(.custom("PearToucan-Regular", size: 30, relativeTo: .title))
                .contentTransition(.numericText())
        }
        .font(.title)
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .frame(minHeight: 60)
        .background(Color.red.opacity(0.3), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 시간 \(viewModel.remainingSeconds)초")
    }

    private var collectionTray: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255).opacity(0.2))

            HStack(spacing: 0) {
                ForEach(0..<viewModel.targetCount, id: \.self) { index in
                    ZStack {
                        collectionCharacter(isTemplate: true)
                            .foregroundStyle(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))

                        if index < viewModel.collectedCount {
                            collectionCharacter(isTemplate: false)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 97, height: 158)
                }
            }
            .frame(width: 291, height: 158)
        }
        .frame(maxWidth: 348)
        .aspectRatio(348 / 158, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("오이 \(viewModel.collectedCount)마리 수집, 목표 \(viewModel.targetCount)마리")
    }

    private func collectionCharacter(isTemplate: Bool) -> some View {
        CucumberCharacterImage(
            imageURL: cucumberImageURL,
            contentMode: .fit,
            isTemplate: isTemplate
        )
        .frame(width: 106, height: 187)
        .offset(x: 3.5, y: 7.5)
    }

}
