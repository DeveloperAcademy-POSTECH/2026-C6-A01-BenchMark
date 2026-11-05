// Created by 이돈혁

import SwiftUI

struct ARGameFailureView: View {
    let onRetry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsRetry = false
    @State private var animationStarted = false

    // Prototype: 1ms delays + 400ms Ease Out × 3, 100ms hold, 300ms final.
    private static let duration = 1.603

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if reduceMotion {
                    glyphs(at: Self.duration, in: geometry.size)
                } else {
                    KeyframeAnimator(initialValue: 0.0, trigger: animationStarted) { time in
                        glyphs(at: time, in: geometry.size)
                    } keyframes: { _ in
                        LinearKeyframe(Self.duration, duration: Self.duration)
                    }
                }
                if reduceMotion || showsRetry {
                    VStack {
                        Spacer()
                        Button(action: onRetry) {
                            Text("재도전")
                                .font(.custom("PearToucan-Regular", size: 30, relativeTo: .title))
                                .tracking(0.6)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 270, height: 70)
                        .background(.white, in: Capsule())
                        .accessibilityHint("AR 수집 게임을 처음부터 다시 시작합니다")
                        .padding(.bottom, max(68, geometry.safeAreaInsets.bottom))
                    }
                }
            }
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("수집 실패")
        .task(id: reduceMotion) {
            guard !reduceMotion else { showsRetry = true; return }
            showsRetry = false
            animationStarted = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            animationStarted = true
            do { try await Task.sleep(for: .seconds(Self.duration)) } catch { return }
            guard !Task.isCancelled else { return }
            showsRetry = true
        }
    }

    private func glyphs(at time: Double, in size: CGSize) -> some View {
        let scale = min(size.width / 402, size.height / 874)
        let origin = CGPoint(x: (size.width - 402 * scale) / 2, y: (size.height - 874 * scale) / 2)
        return ZStack(alignment: .topLeading) {
            ForEach(Self.glyphTracks, id: \.asset) { glyph in
                let pose = glyph.pose(at: time)
                Image(glyph.asset)
                    .resizable()
                    .frame(width: pose.width * scale, height: pose.height * scale)
                    .rotationEffect(.degrees(pose.rotation))
                    .position(x: origin.x + pose.x * scale, y: origin.y + pose.y * scale)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private struct Pose {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let rotation: Double

        func interpolated(to other: Pose, progress: Double) -> Pose {
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * progress }
            return Pose(x: mix(x, other.x), y: mix(y, other.y),
                        width: mix(width, other.width), height: mix(height, other.height),
                        rotation: mix(rotation, other.rotation))
        }
    }

    private struct Glyph {
        let asset: String
        let poses: [Pose]

        func pose(at time: Double) -> Pose {
            let starts = [0.001, 0.402, 0.803, 1.303]
            let durations = [0.4, 0.4, 0.4, 0.3]
            for index in starts.indices {
                if time < starts[index] { return poses[index] }
                let fraction = (time - starts[index]) / durations[index]
                if fraction < 1 {
                    let progress = UnitCurve.easeOut.value(at: max(0, fraction))
                    return poses[index].interpolated(to: poses[index + 1], progress: progress)
                }
            }
            return poses[4]
        }
    }

    // 3750:1621 → 3747:1593 → 3750:1613 → 3750:1605 → 2869:7163.
    // The fourth frame already has the final outlined glyph geometry.
    private static let glyphTracks: [Glyph] = [
        Glyph(asset: "ARGameFailureU", poses: [
            Pose(x: 354.439632, y: 557.278922, width: 202.832565, height: 133.040710, rotation: 17.010301),
            Pose(x: 299.809532, y: 376.495812, width: 93.000000, height: 61.000000, rotation: -15.000000),
            Pose(x: 288.818228, y: 476.635761, width: 84.445831, height: 55.389198, rotation: 18.453806),
            Pose(x: 250.894135, y: 453.949993, width: 42.000000, height: 27.540000, rotation: 0.000000),
            Pose(x: 250.894135, y: 453.949993, width: 42.000000, height: 27.540000, rotation: 0.000000)
        ]),
        Glyph(asset: "ARGameFailurePae", poses: [
            Pose(x: 191.936296, y: 236.425496, width: 163.815369, height: 248.256271, rotation: -15.403797),
            Pose(x: 205.870605, y: 454.548272, width: 97.000000, height: 147.000000, rotation: 15.000000),
            Pose(x: 201.497819, y: 418.948538, width: 70.308304, height: 106.549698, rotation: -13.340181),
            Pose(x: 201.405856, y: 436.520012, width: 41.400000, height: 62.640000, rotation: 0.000000),
            Pose(x: 201.405856, y: 436.520012, width: 41.400000, height: 62.640000, rotation: 0.000000)
        ]),
        Glyph(asset: "ARGameFailureSil", poses: [
            Pose(x: 40.453711, y: 588.595355, width: 180.427124, height: 268.013092, rotation: 13.736310),
            Pose(x: 110.181182, y: 358.535212, width: 103.000000, height: 153.000000, rotation: -13.726092),
            Pose(x: 129.182735, y: 463.941263, width: 69.658073, height: 103.472664, rotation: 9.871150),
            Pose(x: 149.517578, y: 436.520012, width: 42.000000, height: 62.640000, rotation: 0.000000),
            Pose(x: 149.517578, y: 436.520012, width: 42.000000, height: 62.640000, rotation: 0.000000)
        ])
    ]
}

#Preview("Failure 402 × 874", traits: .fixedLayout(width: 402, height: 874)) {
    ARGameFailureView(onRetry: {})
}

#Preview("Small screen", traits: .fixedLayout(width: 375, height: 667)) {
    ARGameFailureView(onRetry: {})
}
