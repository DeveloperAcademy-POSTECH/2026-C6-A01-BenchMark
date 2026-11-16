//
//  ScratchCover.swift
//  OiDonationClip
//
//  Created by jiwon hong on 11/12/26.
//

import SwiftUI

/// The card to scratch on the start view, built from Figma "수집 시작 뷰" > 오이 엽서 (5441:15796).
///
/// Drawn in the 362×502 postcard coordinate space and scaled to the card size, so only the photo
/// differs per NFC tag.
struct ScratchCover: View {
    let photo: UIImage?

    private static let canvas = CGSize(width: 362, height: 502)
    private static let innerCard = CGRect(x: 33, y: 33, width: 296, height: 436)

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.canvas.width
            content
                .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
    }

    private var content: some View {
        let cardShape = RoundedRectangle(cornerRadius: 30)
        let outerShape = RoundedRectangle(cornerRadius: 32)
        return ZStack(alignment: .topLeading) {
            // Hides the postcard's perforated edge outside the inner card.
            Color.white

            ScratchCoverPhoto(photo: photo)
                .frame(width: Self.innerCard.width, height: Self.innerCard.height)
                .clipShape(cardShape)
                .opacity(0.1)
                .offset(x: Self.innerCard.minX, y: Self.innerCard.minY)

            // The 2pt #E8F2E2 stroke sits outside the 296×436 card in Figma.
            outerShape
                .strokeBorder(Color(red: 232 / 255, green: 242 / 255, blue: 226 / 255), lineWidth: 2)
                .frame(width: Self.innerCard.width + 4, height: Self.innerCard.height + 4)
                .offset(x: Self.innerCard.minX - 2, y: Self.innerCard.minY - 2)

            // Soft shadow around the card, drawn over the stroke as in the Figma render (about 15pt, no offset).
            Canvas { context, _ in
                let inner = Path(roundedRect: Self.innerCard, cornerRadius: 30)
                var shadowed = context
                shadowed.addFilter(.shadow(color: .black.opacity(0.12), radius: 8))
                shadowed.fill(inner, with: .color(.white))
                context.blendMode = .clear
                context.fill(inner, with: .color(.white))
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .allowsHitTesting(false)

            // "Vector 29": 217.622×133.854 path rotated 171.57°, centred in its 234.886×164.296 box at (63.88, 173.53).
            ScratchCoverSquiggle()
                .frame(width: 247.624, height: 163.872)
                .rotationEffect(.degrees(171.57))
                .position(x: 63.88 + 234.886 / 2, y: 173.53 + 164.296 / 2)

            Text("여기를 긁어보세요")
                .font(.custom("Paperlogy-6SemiBold", size: 26))
                .tracking(0.52)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 141 / 255, green: 181 / 255, blue: 37 / 255),  // #8DB525
                                 Color(red: 74 / 255, green: 130 / 255, blue: 42 / 255)],   // #4A822A
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .fixedSize()
                .position(x: 180.5, y: 251)
        }
        .accessibilityHidden(true)
    }
}

/// What scratching uncovers: the same photo at full opacity inside the inner card, on white.
///
/// The postcard front stays hidden underneath until scratching is complete.
struct ScratchCoverUnderlay: View {
    let photo: UIImage?

    private static let canvas = CGSize(width: 362, height: 502)
    private static let innerCard = CGRect(x: 33, y: 33, width: 296, height: 436)

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.canvas.width
            ZStack(alignment: .topLeading) {
                Color.white
                ScratchCoverPhoto(photo: photo)
                    .frame(width: Self.innerCard.width, height: Self.innerCard.height)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .offset(x: Self.innerCard.minX, y: Self.innerCard.minY)
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The story photo, or a plain green field when the story has none.
private struct ScratchCoverPhoto: View {
    let photo: UIImage?

    var body: some View {
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
        } else {
            Color(red: 112 / 255, green: 140 / 255, blue: 64 / 255)
        }
    }
}

/// Figma "Vector 29" stroke, copied from its SVG (247.624×163.872 viewBox).
private struct ScratchCoverSquiggle: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 247.624
            let sy = size.height / 163.872
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

            var path = Path()
            path.move(to: p(15.0007, 54.374))
            path.addCurve(to: p(85.3431, 16.2697), control1: p(15.0007, 54.374), control2: p(51.8748, 6.76325))
            path.addCurve(to: p(69.7203, 138.803), control1: p(129.413, 28.7876), control2: p(28.7587, 118.285))
            path.addCurve(to: p(186.902, 40.4112), control1: p(109.779, 158.87), control2: p(156.276, 18.5389))
            path.addCurve(to: p(169.667, 146.531), control1: p(215.699, 60.9777), control2: p(140.773, 130.998))
            path.addCurve(to: p(232.622, 105.074), control1: p(196.205, 160.798), control2: p(232.622, 105.074))

            let gradient = Gradient(stops: [
                .init(color: Color(red: 144 / 255, green: 205 / 255, blue: 118 / 255), location: 0.331962), // #90CD76
                .init(color: Color(red: 5 / 255, green: 127 / 255, blue: 66 / 255), location: 1)              // #057F42
            ])
            context.opacity = 0.4
            context.stroke(
                path,
                with: .linearGradient(gradient, startPoint: p(234.827, 180.95), endPoint: p(7.32371, -6.40679)),
                style: StrokeStyle(lineWidth: 30 * sx, lineCap: .round)
            )
        }
    }
}
