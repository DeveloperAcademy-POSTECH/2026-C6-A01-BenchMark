//
//  ARGameIntroView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGameIntroView: View {
    let cucumberName: String
    let targetCount: Int
    let timeLimitSeconds: Int
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            let origin = CGPoint(
                x: (geometry.size.width - 402 * scale) / 2,
                y: (geometry.size.height - 874 * scale) / 2
            )

            ZStack {
                Image("ARGameIntroBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                Color.black.opacity(0.4)
                    .accessibilityHidden(true)

                backButton(scale: scale, origin: origin)

                Text("오이 수집 게임")
                    .font(pearFont(size: 25 * scale, relativeTo: .title2, bold: true))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .position(x: origin.x + 201 * scale, y: origin.y + 91 * scale)
                    .accessibilityAddTraits(.isHeader)

                cucumberArtwork(scale: scale, origin: origin)

                Text(cucumberName)
                    .font(pearFont(size: 20 * scale, relativeTo: .title3, bold: false))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 30 * scale)
                    .frame(minHeight: 44 * scale)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 222 / 255, green: 237 / 255, blue: 250 / 255),
                                Color(red: 93 / 255, green: 180 / 255, blue: 240 / 255)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .frame(maxWidth: 362 * scale)
                    .position(x: origin.x + 201 * scale, y: origin.y + 505 * scale)

                targetText(scale: scale)
                    .position(x: origin.x + 201 * scale, y: origin.y + 621 * scale)

                Text("제한시간 \(timeLimitSeconds)초")
                    .font(pearFont(size: 16 * scale, relativeTo: .body, bold: true))
                    .foregroundStyle(.red)
                    .shadow(color: .white, radius: 12 * scale)
                    .position(x: origin.x + 201 * scale, y: origin.y + 727 * scale)

                startButton(scale: scale, origin: origin)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private func backButton(scale: CGFloat, origin: CGPoint) -> some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 19 * scale, weight: .semibold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .position(x: origin.x + 45 * scale, y: origin.y + 91 * scale)
        .accessibilityLabel("이전 화면")
    }

    private func cucumberArtwork(scale: CGFloat, origin: CGPoint) -> some View {
        ZStack {
            Image("ARGameIntroGlow")
                .resizable()
                .scaledToFit()
                .frame(width: 248 * scale, height: 343 * scale)
                .opacity(0.55)
                .blur(radius: 24 * scale)

            Image("ARGameIntroCucumber")
                .resizable()
                .scaledToFill()
                .frame(width: 212 * scale, height: 338 * scale)
                .clipped()
        }
        .rotationEffect(.degrees(0))
        .position(x: origin.x + 201 * scale, y: origin.y + 309 * scale)
        .accessibilityHidden(true)
    }

    private func targetText(scale: CGFloat) -> some View {
        (Text("\(targetCount)마리")
            .foregroundStyle(Color(red: 240 / 255, green: 255 / 255, blue: 143 / 255))
        + Text("를 찾으세요!")
            .foregroundStyle(.white))
        .font(pearFont(size: 40 * scale, relativeTo: .largeTitle, bold: true))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityLabel("\(targetCount)마리를 찾으세요")
    }

    private func startButton(scale: CGFloat, origin: CGPoint) -> some View {
        Button(action: onStart) {
            Text("시작")
                .font(pearFont(size: 20 * scale, relativeTo: .title3, bold: true))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: max(56 * scale, 50))
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: min(362 * scale, 362))
        .contentShape(Capsule())
        .position(x: origin.x + 201 * scale, y: origin.y + 775 * scale)
        .accessibilityHint("카메라 권한을 확인하고 AR 게임을 시작합니다")
    }

    private func pearFont(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        bold: Bool
    ) -> Font {
        let font = Font.custom("PearToucan-Regular", size: size, relativeTo: textStyle)
        return bold ? font.weight(.bold) : font
    }
}

#Preview("AR 게임 시작", traits: .fixedLayout(width: 402, height: 874)) {
    ARGameIntroView(
        cucumberName: "화성갈끄니까오이",
        targetCount: 3,
        timeLimitSeconds: 30,
        onBack: {},
        onStart: {}
    )
}

#Preview("작은 화면", traits: .fixedLayout(width: 375, height: 667)) {
    ARGameIntroView(
        cucumberName: "아주 긴 이름을 가진 우주 오이",
        targetCount: 3,
        timeLimitSeconds: 30,
        onBack: {},
        onStart: {}
    )
}
