//
//  ARGameSuccessView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGameSuccessView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        GeometryReader { geometry in
            let scale = max(
                geometry.size.width / 402,
                geometry.size.height / 874
            )

            ZStack(alignment: .topLeading) {
                Color.black
                    .frame(width: 402, height: 874)

                expandingCircle(
                    center: CGPoint(x: 104, y: 174),
                    expandedDiameter: 700
                )
                expandingCircle(
                    center: CGPoint(x: 342, y: 368),
                    expandedDiameter: 500
                )
                expandingCircle(
                    center: CGPoint(x: 180.5, y: 683.5),
                    expandedDiameter: 585
                )

                Text("성공!")
                    .font(.custom("PearToucan-Regular", size: 60, relativeTo: .largeTitle).weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(isExpanded ? successGreen : .white)
                    .fixedSize()
                    .position(x: 200.5, y: 437)
            }
            .frame(width: 402, height: 874, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(
                x: (geometry.size.width - 402 * scale) / 2,
                y: (geometry.size.height - 874 * scale) / 2
            )
        }
        .ignoresSafeArea()
        .task {
            isExpanded = reduceMotion
            if !reduceMotion {
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.8)) {
                    isExpanded = true
                }
            }

            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private var successGreen: Color {
        Color(red: 146 / 255, green: 187 / 255, blue: 55 / 255)
    }

    private func expandingCircle(
        center: CGPoint,
        expandedDiameter: CGFloat
    ) -> some View {
        Circle()
            .fill(Color(red: 243 / 255, green: 247 / 255, blue: 230 / 255))
            .frame(
                width: isExpanded ? expandedDiameter : 10,
                height: isExpanded ? expandedDiameter : 10
            )
            .position(center)
            .accessibilityHidden(true)
    }
}

#Preview {
    ARGameSuccessView(onFinished: {})
}
