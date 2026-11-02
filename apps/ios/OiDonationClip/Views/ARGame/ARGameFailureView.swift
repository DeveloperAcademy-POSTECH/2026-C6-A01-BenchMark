//
//  ARGameFailureView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGameFailureView: View {
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var showsRetry = false

    private let stageAssets = [
        "ARGameFailureStage1",
        "ARGameFailureStage2",
        "ARGameFailureStage3",
        "ARGameFailureStage4"
    ]

    var body: some View {
        ZStack {
            Color.black

            Image(stageAssets[stage])
                .resizable()
                .scaledToFill()
                .id(stage)
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                .accessibilityHidden(true)

            if showsRetry {
                VStack {
                    Spacer()

                    Button(action: onRetry) {
                        Text("재도전")
                            .font(.custom("PearToucan-Regular", size: 30, relativeTo: .title))
                            .tracking(0.6)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 270, height: 70)
                    .background(.white, in: Capsule())
                    .accessibilityHint("AR 수집 게임을 처음부터 다시 시작합니다")
                    .padding(.bottom, 68)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("수집 실패")
        .task {
            if reduceMotion {
                stage = stageAssets.count - 1
                showsRetry = true
                return
            }

            for nextStage in 1..<stageAssets.count {
                do {
                    try await Task.sleep(for: .milliseconds(180))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    stage = nextStage
                }
            }

            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showsRetry = true
            }
        }
    }
}

#Preview {
    ARGameFailureView(onRetry: {})
}
