//
//  ARGameIntroView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGameIntroView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var accessibleTitleWidth = 140
    let cucumberName: String
    let cucumberImageURL: URL?
    var cucumberAssetName: String? = nil
    var showsControls = true
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

                Color.black.opacity(showsControls ? 0.4 : 0)
                    .accessibilityHidden(true)

                if showsControls {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            accessibleContent
                        } else {
                            standardContent(scale: scale, origin: origin)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private func standardContent(scale: CGFloat, origin: CGPoint) -> some View {
        backButton(scale: scale, origin: origin)

        titleArtwork
            .frame(width: 140 * scale, height: 27 * scale)
            .position(x: origin.x + 200 * scale, y: origin.y + 91 * scale)
            .accessibilityAddTraits(.isHeader)

        cucumberArtwork(scale: scale, origin: origin)

        Text(cucumberName)
            .font(pearFont(size: 20 * scale, relativeTo: .title3, bold: false))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 30 * scale)
            .frame(minHeight: 44 * scale)
            .background(Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255), in: Capsule())
            .frame(maxWidth: 362 * scale)
            .position(x: origin.x + 201 * scale, y: origin.y + 505 * scale)

        targetText(scale: scale)
            .position(x: origin.x + 201 * scale, y: origin.y + 637 * scale)

        startButton(scale: scale, origin: origin)
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
                .frame(width: 366.982 * scale, height: 508.575 * scale)
                .rotationEffect(.degrees(16.56))
                // Restore Figma's stdDeviation 50, unsupported by Asset Catalog SVG.
                .blur(radius: 50 * scale)
                .position(x: origin.x + 201 * scale, y: origin.y + 311.6835 * scale)

            // The 212.429 × 337.504 crop slot paints this alpha-bounded region.
            // Normalize all sources first so remote padding cannot change visual size.
            CucumberCharacterImage(imageURL: cucumberImageURL, contentMode: .fit, assetName: cucumberAssetName)
                .frame(width: 189.331444 * scale, height: 312.508397 * scale)
                .position(x: origin.x + 193.354493 * scale, y: origin.y + 311.238019 * scale)
        }
        .accessibilityHidden(true)
    }

    private func targetText(scale: CGFloat) -> some View {
        let highlight = Color(red: 240 / 255, green: 255 / 255, blue: 143 / 255)
        let timeLimit = Text("\(timeLimitSeconds)초").foregroundStyle(highlight)
        let target = Text("\(targetCount)마리").foregroundStyle(highlight)

        return Text("\(timeLimit) 안에\n\(target)를 찾으세요!")
            .foregroundStyle(.white)
            .font(pearFont(size: 40 * scale, relativeTo: .largeTitle, bold: false))
            .multilineTextAlignment(.center)
            .lineSpacing(20 * scale)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .accessibilityLabel("\(timeLimitSeconds)초 안에 \(targetCount)마리를 찾으세요")
    }

    private func startButton(scale: CGFloat, origin: CGPoint) -> some View {
        Button(action: onStart) {
            Text("시작")
                .font(.custom("Paperlogy-7Bold", fixedSize: 20 * scale))
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
        let font = dynamicTypeSize.isAccessibilitySize
            ? Font.custom("Paperlogy-4Regular", size: size, relativeTo: textStyle)
            : Font.custom("Paperlogy-4Regular", fixedSize: size)
        return bold ? font.weight(.bold) : font
    }

    private var accessibleContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").frame(width: 50, height: 50)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("이전 화면")
                    titleArtwork
                        .aspectRatio(140 / 27, contentMode: .fit)
                        .frame(maxWidth: accessibleTitleWidth)
                        .accessibilityAddTraits(.isHeader)
                }
                CucumberCharacterImage(imageURL: cucumberImageURL, contentMode: .fit, assetName: cucumberAssetName)
                    .frame(height: 260)
                    .accessibilityHidden(true)
                Text(cucumberName)
                    .font(pearFont(size: 20, relativeTo: .title3, bold: false))
                    .foregroundStyle(.black)
                    .padding(16)
                    .background(Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255), in: RoundedRectangle(cornerRadius: 30))
                Text("\(timeLimitSeconds)초 안에 \(targetCount)마리를 찾으세요!")
                    .font(pearFont(size: 40, relativeTo: .largeTitle, bold: false))
                    .lineSpacing(24)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                Button(action: onStart) {
                    Text("시작")
                        .font(.custom("Paperlogy-7Bold", size: 20, relativeTo: .title3))
                        .foregroundStyle(.black)
                        .padding(20)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("카메라 권한을 확인하고 AR 게임을 시작합니다")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 66)
            .padding(.bottom, 68)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // The original static title outlines preserve Figma Bold without substituting a font.
    private var titleArtwork: some View {
        Image("ARGameIntroTitle")
            .resizable()
            .accessibilityLabel("오이 수집 게임")
    }
}

#Preview("AR 게임 시작", traits: .fixedLayout(width: 402, height: 874)) {
    ARGameIntroView(
        cucumberName: "화성갈끄니까오이",
        cucumberImageURL: nil,
        targetCount: 3,
        timeLimitSeconds: 30,
        onBack: {},
        onStart: {}
    )
}

#Preview("작은 화면", traits: .fixedLayout(width: 375, height: 667)) {
    ARGameIntroView(
        cucumberName: "아주 긴 이름을 가진 우주 오이",
        cucumberImageURL: nil,
        targetCount: 3,
        timeLimitSeconds: 30,
        onBack: {},
        onStart: {}
    )
}
