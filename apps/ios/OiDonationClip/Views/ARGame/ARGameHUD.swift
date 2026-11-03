// Created by 이돈혁

import SwiftUI

struct ARGameHUD: View {
    let remainingSeconds: Int
    let collectedCount: Int
    let targetCount: Int
    let cucumberImageURL: URL?
    var cucumberAssetName: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack {
                timer
                    .padding(.top, max(73, geometry.safeAreaInsets.top + 8))
                Spacer()
                collectionTray(width: min(348, geometry.size.width - 54))
                    .padding(.bottom, max(36, geometry.safeAreaInsets.bottom + 2))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var timer: some View {
        HStack(spacing: 13) {
            Image(systemName: "clock.fill")
                .font(.system(size: 30))
            Text("\(remainingSeconds)")
                .font(.custom("PearToucan-Regular", fixedSize: 30))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .frame(width: 144, height: 60)
        .background(Color.red.opacity(0.2), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 시간 \(remainingSeconds)초")
    }

    private func collectionTray(width: CGFloat) -> some View {
        ZStack {
            Image("ARGameCollectionTray")
                .resizable()
                .accessibilityHidden(true)
            HStack(spacing: 25) {
                ForEach(0..<targetCount, id: \.self) { index in
                    ZStack {
                        if index < collectedCount {
                            CucumberCharacterImage(imageURL: cucumberImageURL, contentMode: .fit, assetName: cucumberAssetName)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 72, height: 118)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: collectedCount)
        }
        .frame(width: 348, height: 158)
        .scaleEffect(width / 348)
        .frame(width: width, height: 158 * width / 348)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("오이 \(collectedCount)마리 수집, 목표 \(targetCount)마리")
    }
}
