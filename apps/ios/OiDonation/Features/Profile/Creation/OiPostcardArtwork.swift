//
//  OiPostcardArtwork.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import SwiftUI
import UIKit

/// Figma 5400:6051. All coordinates use the 362 × 502 postcard canvas.
struct OiPostcardPaper: View {
    var body: some View {
        Image("OiPostcardPaper").renderingMode(.template).resizable()
    }
}

struct OiPostcardFront<Artwork: View>: View {
    var fill: OiDraftCustomization.Fill = .gradient
    var first: UInt32 = 0xE8EECF
    var second: UInt32 = 0xD5DBC6
    var date = ""
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        ZStack(alignment: .topLeading) {
            OiCardGradient(fill: fill, first: first, second: second)
            artwork().frame(width: 296, height: 436).clipped().offset(x: 33, y: 33)
            ForEach(0..<3) { index in
                Image("OiPostcardWave\(index + 1)").resizable()
                    .frame(width: 121, height: index == 1 ? 17 : 16)
                    .offset(x: 23, y: CGFloat(26 + index * 13))
                    .accessibilityHidden(true)
            }
            Text(date).font(.system(size: 17, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 150, height: 24, alignment: .trailing).offset(x: 167, y: 41)
                .accessibilityLabel("작성 날짜 \(date)")
            Text("OiD").font(.system(size: 17, weight: .light, design: .rounded)).tracking(1.12)
                .foregroundStyle(.white).fixedSize().rotationEffect(.degrees(-90))
                .frame(width: 21, height: 58).offset(x: 43, y: 396)
                .accessibilityHidden(true)
            Image("OiPostcardSeal").renderingMode(.template).resizable()
                .foregroundStyle(Color(oiRGB: OiPostcardInk.color(first)))
                .frame(width: 116, height: 116).offset(x: 229, y: 365)
                .accessibilityHidden(true)
        }.frame(width: 362, height: 502).mask(OiPostcardPaper()).dynamicTypeSize(.medium)
    }
}

struct OiPostcardBack: View {
    var fill: OiDraftCustomization.Fill = .gradient
    var first: UInt32 = 0xE8EECF
    var second: UInt32 = 0xD5DBC6
    let message: String
    let author: String
    var scrollable = false
    private var ink: Color { Color(oiRGB: OiPostcardInk.color(first)) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            OiCardGradient(fill: fill, first: first, second: second)
            Image("OiPostcardWatermark").renderingMode(.template).resizable()
                .foregroundStyle(ink.opacity(0.15))
                .frame(width: 213, height: 213).offset(x: 129, y: 259)
                .accessibilityHidden(true)
            Group {
                if scrollable {
                    ScrollView { letter.fixedSize(horizontal: false, vertical: true) }.scrollIndicators(.hidden)
                } else { letter.minimumScaleFactor(0.6) }
            }.frame(width: 292, height: 389, alignment: .topLeading).offset(x: 35, y: 30)
            Text("FROM").font(.system(size: 7, weight: .light, design: .serif)).italic()
                .offset(x: 35, y: 443)
            Text(author).font(CampusStyle.body(12)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 292, height: 20, alignment: .leading).offset(x: 35, y: 453)
        }.foregroundStyle(ink).frame(width: 362, height: 502)
            .mask(OiPostcardPaper()).dynamicTypeSize(.medium)
    }
    private var letter: some View {
        Text(message.isEmpty ? "아직 남긴 이야기가 없어요." : message)
            .font(CampusStyle.hand(17)).tracking(0.17).lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Keep ink readable even for dark or custom RGB paper colors.
enum OiPostcardInk {
    static func color(_ rgb: UInt32) -> UInt32 {
        switch rgb {
        case 0xE8EECF: return 0x323F1D
        case 0xE8D8E8: return 0x3F1D2C
        case 0xF1D8D6: return 0x3F1D1D
        default: break
        }
        let r = Double((rgb >> 16) & 255), g = Double((rgb >> 8) & 255), b = Double(rgb & 255)
        if r * 0.2126 + g * 0.7152 + b * 0.0722 < 105 { return 0xFFFFFF }
        return UInt32(r * 0.28) << 16 | UInt32(g * 0.28) << 8 | UInt32(b * 0.28)
    }
}

/// Only a horizontal gesture flips; vertical drags remain available for reading.
enum OiPostcardFlip {
    static func accepts(_ translation: CGSize) -> Bool {
        abs(translation.width) >= 35 && abs(translation.width) > abs(translation.height) * 1.3
    }
}

struct OiFlippablePostcard<Front: View, Back: View>: View {
    @Binding var showingBack: Bool
    @ViewBuilder var front: () -> Front
    @ViewBuilder var back: () -> Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    var body: some View {
        GeometryReader { proxy in
            Group {
                if showingBack { back() } else { front() }
            }.frame(width: 362, height: 502)
                .scaleEffect(proxy.size.width / 362, anchor: .topLeading)
        }.aspectRatio(362 / 502, contentMode: .fit)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .contentShape(Rectangle())
            .onTapGesture { flip() }
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                if OiPostcardFlip.accepts(value.translation) { flip() }
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("엽서 \(showingBack ? "뒷면" : "앞면")")
            .accessibilityHint("탭하거나 옆으로 밀어서 뒤집기")
            .accessibilityAction(named: "엽서 뒤집기") { flip() }
            .accessibilityIdentifier("oi.postcard.flip")
    }
    private func flip() {
        guard angle == 0 else { return }
        if reduceMotion { showingBack.toggle(); return }
        withAnimation(.easeIn(duration: 0.16), completionCriteria: .logicallyComplete) { angle = 90 } completion: {
            showingBack.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.16)) { angle = 0 }
        }
    }
}

enum OiPostcardDate {
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yy.MM.dd"
        return formatter.string(from: date)
    }
    static func string(from value: String) -> String {
        let numbers = value.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard numbers.count >= 3 else { return value }
        return String(format: "%02d.%02d.%02d", (Int(numbers[0]) ?? 0) % 100, Int(numbers[1]) ?? 0, Int(numbers[2]) ?? 0)
    }
}
