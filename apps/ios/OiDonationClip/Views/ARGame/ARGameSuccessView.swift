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
            let scale = min(
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

                Image("ARGameSuccessTitle")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 120, height: 64)
                    .foregroundStyle(isExpanded ? successGreen : .white)
                    .position(x: 200.5, y: 437)
                    .accessibilityLabel("수집 성공")
            }
            .frame(width: 402, height: 874, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(
                x: (geometry.size.width - 402 * scale) / 2,
                y: (geometry.size.height - 874 * scale) / 2
            )
        }
        .background(Color.black)
        .clipped()
        .ignoresSafeArea()
        .task(id: reduceMotion) {
            isExpanded = reduceMotion
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(1)) } catch { return }
                withAnimation(.timingCurve(0, 0, 0.58, 1, duration: 0.6)) {
                    isExpanded = true
                }
            }

            do {
                if !reduceMotion { try await Task.sleep(for: .milliseconds(600)) }
                try await Task.sleep(for: .milliseconds(400))
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
