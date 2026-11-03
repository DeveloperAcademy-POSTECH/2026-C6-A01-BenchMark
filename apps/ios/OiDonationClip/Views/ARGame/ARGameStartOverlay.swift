//
//  ARGameStartOverlay.swift
//  OiDonationClip
//
//  Created by 이돈혁
//

import SwiftUI

struct ARGameStartOverlay: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAssembled = false
    @State private var isVisible = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            GeometryReader { geometry in
                let scale = min(
                    geometry.size.width / 402,
                    geometry.size.height / 874
                )

                ZStack(alignment: .topLeading) {
                    glyphs
                }
                .frame(width: 402, height: 874, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(
                    x: (geometry.size.width - 402 * scale) / 2,
                    y: (geometry.size.height - 874 * scale) / 2
                )
            }
        }
        .opacity(isVisible ? 1 : 0)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("수집 시작")
        .task(id: reduceMotion) {
            isVisible = true
            isAssembled = reduceMotion

            if !reduceMotion {
                await Task.yield()
                withAnimation(.timingCurve(0, 0, 0.58, 1, duration: 0.7)) {
                    isAssembled = true
                }
            }

            do {
                if !reduceMotion { try await Task.sleep(for: .milliseconds(700)) }
                try await Task.sleep(for: .milliseconds(200))
                if !reduceMotion {
                    withAnimation(.timingCurve(0, 0, 0.58, 1, duration: 0.4)) { isVisible = false }
                    try await Task.sleep(for: .milliseconds(400))
                }
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    @ViewBuilder
    private var glyphs: some View {
        startGlyph(
            asset: "ARGameStartSiot",
            size: CGSize(width: 27.54, height: 61.92),
            start: CGPoint(x: -200.98, y: 241.59),
            end: CGPoint(x: 154.27, y: 436.76),
            startSize: CGSize(width: 125, height: 281),
            startRotation: -21.17
        )
        startGlyph(
            asset: "ARGameStartI",
            size: CGSize(width: 9, height: 62.46),
            start: CGPoint(x: 84.5, y: -247.5),
            end: CGPoint(x: 178, y: 436.43),
            startSize: CGSize(width: 41, height: 281)
        )
        startGlyph(
            asset: "ARGameStartJieut",
            size: CGSize(width: 27.36, height: 31.5),
            start: CGPoint(x: -168.54, y: 874.11),
            end: CGPoint(x: 204.57, y: 421.55),
            startSize: CGSize(width: 157, height: 181),
            startRotation: 17.73
        )
        startGlyph(
            asset: "ARGameStartA",
            size: CGSize(width: 15, height: 31.98),
            start: CGPoint(x: 595.41, y: 862.52),
            end: CGPoint(x: 228.99, y: 421.19),
            startSize: CGSize(width: 84.418938, height: 181.072479),
            startRotation: -15.72
        )
        startGlyph(
            asset: "ARGameStartGiyeok",
            size: CGSize(width: 39.6, height: 28.2),
            start: CGPoint(x: 213.48, y: 1025.03),
            end: CGPoint(x: 212.49, y: 453.62),
            startSize: CGSize(width: 140, height: 100),
            startRotation: 6.89
        )
        startGlyph(
            asset: "ARGameStartBar",
            size: CGSize(width: 9, height: 46.68),
            start: CGPoint(x: 579.43, y: 88.03),
            end: CGPoint(x: 252.32, y: 428.54),
            startSize: CGSize(width: 74, height: 384),
            startRotation: 15
        )
        startGlyph(
            asset: "ARGameStartDot",
            size: CGSize(width: 14.28, height: 13.86),
            start: CGPoint(x: 607, y: 437.5),
            end: CGPoint(x: 252.44, y: 461.27),
            startSize: CGSize(width: 56, height: 55)
        )
    }

    private func startGlyph(
        asset: String,
        size: CGSize,
        start: CGPoint,
        end: CGPoint,
        startSize: CGSize,
        startRotation: Double = 0
    ) -> some View {
        Image(asset)
            .resizable()
            .frame(
                width: isAssembled ? size.width : startSize.width,
                height: isAssembled ? size.height : startSize.height
            )
            .rotationEffect(.degrees(isAssembled ? 0 : startRotation))
            .position(isAssembled ? end : start)
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Image("ARGameIntroBackground")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
        ARGameStartOverlay(onFinished: {})
    }
}
