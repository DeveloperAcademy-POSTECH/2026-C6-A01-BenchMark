//
//  AppClipStartView.swift
//  OiDonationClip
//
//  Created by Jiwon Hong on 11/16/26.
//

import SwiftUI

/// Figma `6005:5306` (App Clip 시작 뷰): shown when the App Clip opens without an NFC postcard tag (#351).
/// The artwork keeps the 402pt design coordinates and scales to fit; the download panel spans the full width.
struct AppClipStartView: View {
    let onDownload: () -> Void

    /// Design area above the 93pt download panel.
    private static let canvas = CGSize(width: 402, height: 781)
    private static let panelHeight: CGFloat = 93
    private static let green = Color(red: 0x70 / 255, green: 0x8C / 255, blue: 0x40 / 255)
    private static let mint = Color(red: 0xD8 / 255, green: 0xE9 / 255, blue: 0xC6 / 255)

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size // Full screen: the reader ignores the safe area below.
            let scale = min(screen.width / Self.canvas.width,
                            (screen.height - Self.panelHeight) / Self.canvas.height)
            ZStack(alignment: .topLeading) {
                background(scale: scale, width: screen.width)
                artwork
                    .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale, alignment: .topLeading)
                    .frame(width: screen.width)
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
            .overlay(alignment: .bottom) { downloadPanel }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
    }

    /// #708C40 with two softly blurred ellipses (#435426 top right, #B0C85B 70% left), per the design SVG.
    private func background(scale: CGFloat, width: CGFloat) -> some View {
        let x = (width - Self.canvas.width * scale) / 2
        return ZStack(alignment: .topLeading) {
            Self.green
            Ellipse().fill(Color(red: 0x43 / 255, green: 0x54 / 255, blue: 0x26 / 255))
                .frame(width: 393 * scale, height: 278 * scale)
                .position(x: x + 317.5 * scale, y: 10 * scale)
                .blur(radius: 47.35 * scale)
            Ellipse().fill(Color(red: 0xB0 / 255, green: 0xC8 / 255, blue: 0x5B / 255)).opacity(0.7)
                .frame(width: 392 * scale, height: 219 * scale)
                .position(x: x + 75 * scale, y: 251.5 * scale)
                .blur(radius: 47.35 * scale)
        }
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            header
            Image("ClipStartAppLogo").resizable().frame(width: 47.35, height: 47.35)
                .frame(width: 47.332, height: 47.332)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 11.833))
                .offset(x: 70, y: 200.29)
                .accessibilityHidden(true)
            Image("ClipStartWordmark").resizable().frame(width: 198.869, height: 47.35)
                .offset(x: 131.1, y: 200.4)
                .accessibilityLabel("오이기부")
                .accessibilityAddTraits(.isHeader)
            subtitle.position(x: 200, y: 287)
            steps
        }
    }

    /// Figma sets the subtitle in 나눔손글씨 엉겅퀴체 26pt. That 5.1MB font would push the App Clip past
    /// 15MB, so Paperlogy stands in. Each word keeps the width its Nanum glyphs take at 26pt and the
    /// word gaps stay 7.8pt, so the line matches Figma's width and spacing; letters are spaced evenly
    /// inside each word because the handwritten 기 is far narrower than Paperlogy's.
    private static let subtitleWords: [(String, CGFloat)] = [
        ("작은", 35.21), ("기부로", 43.01), ("학교를", 52.99), ("바꾸다", 48.75)
    ]

    private var subtitle: some View {
        HStack(spacing: 7.8) {
            ForEach(Self.subtitleWords, id: \.0) { word, width in
                HStack(spacing: 0) {
                    ForEach(Array(word.enumerated()), id: \.offset) { _, letter in
                        Text(String(letter)).fixedSize().frame(width: width / CGFloat(word.count))
                    }
                }
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 17))
        .foregroundStyle(.white)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("작은 기부로 학교를 바꾸다")
    }

    /// BenchMark logo, rule and team names (Figma `6005:7749`).
    private var header: some View {
        ZStack(alignment: .topLeading) {
            Image("ClipStartBenchMarkLogo").resizable().frame(width: 23.238, height: 26.434)
                .rotationEffect(.degrees(3.14))
                .position(x: 20 + 24.653 / 2, y: 64 + 27.669 / 2)
            // EF 제주돌담 is not bundled; Paperlogy keeps the 6pt wordmark letters.
            Text("ench").offset(x: 40.26, y: 78.66)
            Text("ark").offset(x: 44.25, y: 84.04)
            Self.mint.frame(width: 66, height: 0.3).offset(x: 68, y: 79.35)
            Text(verbatim: "Doony   Eepy   Jun   Kaelyn   Soori   Spero")
                .font(.custom("Paperlogy-4Regular", size: 12))
                .foregroundStyle(Color(red: 0x88 / 255, green: 0x9D / 255, blue: 0x71 / 255))
                .fixedSize()
                .frame(width: 382, height: 24, alignment: .trailing)
                .offset(y: 67)
        }
        .font(.custom("Paperlogy-7Bold", size: 6.328))
        .foregroundStyle(Self.mint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("벤치마크 팀: Doony, Eepy, Jun, Kaelyn, Soori, Spero")
    }

    private var steps: some View {
        ZStack(alignment: .topLeading) {
            step("1. 학교에 기부 & 인증 하고", x: 151.5, y: 422.5)
            arrow(x: 197, y: 444)
            step("2. 모교에서의 이야기를 남기고", x: 232, y: 508.5)
            arrow(x: 164, y: 534, mirrored: true)
            step("3. 우표와 오이를 커스텀하여", x: 158, y: 594.5)
            arrow(x: 197, y: 622)
            step("4. 동문들과 추억을 나눠보세요!", x: 231, y: 680.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func step(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(.custom("Paperlogy-3Light", size: 16))
            .foregroundStyle(.white)
            .fixedSize()
            .position(x: x, y: y)
    }

    private func arrow(x: CGFloat, y: CGFloat, mirrored: Bool = false) -> some View {
        Image("ClipStartArrow").resizable().frame(width: 41, height: 35)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .offset(x: x, y: y)
            .accessibilityHidden(true)
    }

    /// Figma `6005:7765`: #EAEEE2 panel with a 25pt top radius and a full-width green button.
    private var downloadPanel: some View {
        Button(action: onDownload) {
            Text("앱 다운로드 하기")
                .font(.custom("Paperlogy-5Medium", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Self.green, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityHint("오이기부 전체 앱 설치 화면을 열어요")
        .accessibilityIdentifier("appclip.start.download")
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, minHeight: Self.panelHeight, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)
                .fill(Color(red: 0xEA / 255, green: 0xEE / 255, blue: 0xE2 / 255))
                .shadow(color: .black.opacity(0.4), radius: 3, y: -1)
        }
    }
}

#Preview {
    AppClipStartView(onDownload: {})
}
