//
//  OiSeedCucumberCustomizationView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/9/26.
//

import SwiftUI

struct OiSeedCucumberCustomizationView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appearance: OiSeedCucumberAppearance
    @State private var selection: OiSeedCucumberPart

    init(appearance: OiSeedCucumberAppearance = .init(), selection: OiSeedCucumberPart = .eyes) {
        _appearance = State(initialValue: appearance)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                preview
                    .frame(height: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.4 : 0.53))
                Divider()
                ScrollView {
                    controls
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("오이 커스텀")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preview: some View {
        Canvas { context, size in
            let viewport = OiSeedCucumberViewport(size: size)
            var artwork = context
            artwork.concatenate(viewport.transform)
            var stem = artwork
            stem.concatenate(appearance.stemTransform)
            let stemLayer = OiSeedCucumberLayer.stem
            stem.draw(Image(stemLayer.asset), in: stemLayer.sourceFrame)
            // The crown covers the stem's cut edge at every rotation and length.
            artwork.draw(Image("SeedCucumberBody"), in: appearance.bodyFrame)
            for layer in OiSeedCucumberLayer.faceLayers {
                artwork.draw(Image(layer.asset), in: appearance.faceFrame(layer))
            }
            drawSelection(in: context, viewport: viewport)
        }
        .overlay {
            OiSeedCucumberTouchSurface(appearance: $appearance, selection: $selection)
        }
        .accessibilityHidden(true)
    }

    private func drawSelection(in context: GraphicsContext, viewport: OiSeedCucumberViewport) {
        let markers: [CGRect]
        if selection == .stem {
            let tip = viewport.location(of: appearance.stemTip)
            markers = [CGRect(x: tip.x - 8, y: tip.y - 8, width: 16, height: 16)]
        } else {
            markers = OiSeedCucumberLayer.faceLayers.filter { $0.part == selection }.map { layer in
                appearance.faceFrame(layer).applying(viewport.transform).insetBy(dx: -4, dy: -4)
            }
        }
        for marker in markers {
            let outline = Path(roundedRect: marker, cornerRadius: min(marker.width, marker.height) / 2)
            context.stroke(outline, with: .color(.white), lineWidth: 3)
            context.stroke(outline, with: .color(.primary), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                partPicker.pickerStyle(.menu)
            } else {
                partPicker.pickerStyle(.segmented)
            }
            Text(instructions)
                .font(.footnote)
                .foregroundStyle(.secondary)
            switch selection {
            case .stem:
                slider("길이", value: $appearance.stemLength, range: OiSeedCucumberAppearance.lengthRange,
                       display: percent(appearance.stemLength), id: "length")
                slider("각도", value: $appearance.stemAngle, range: OiSeedCucumberAppearance.angleRange,
                       display: "\(Int(appearance.stemAngle.rounded()))°", id: "angle")
            case .body:
                slider("키", value: $appearance.bodyHeight, range: OiSeedCucumberAppearance.heightRange,
                       display: percent(appearance.bodyHeight), id: "height")
                slider("체형", value: $appearance.bodyWidth, range: OiSeedCucumberAppearance.widthRange,
                       display: percent(appearance.bodyWidth), id: "width")
            case .eyes, .mouth:
                let face = appearance[selection]
                slider("크기", value: faceBinding(\.size), range: OiSeedCucumberAppearance.sizeRange,
                       display: percent(face.size), id: "size")
                slider("좌우 위치", value: faceBinding(\.x), range: OiSeedCucumberAppearance.horizontalRange,
                       display: offsetLabel(face.x, negative: "왼쪽", positive: "오른쪽"), id: "horizontal")
                slider("상하 위치", value: faceBinding(\.y), range: OiSeedCucumberAppearance.verticalRange,
                       display: offsetLabel(face.y, negative: "위", positive: "아래"), id: "vertical")
            }
        }
    }

    private var instructions: String {
        switch selection {
        case .eyes: "두 눈을 함께 끌어 옮기고, 두 손가락으로 크기를 조절하세요."
        case .mouth: "입을 끌어 옮기고, 두 손가락으로 크기를 조절하세요."
        case .stem: "꼭지 끝을 끌어 길이와 각도를 조절하세요."
        case .body: "키와 체형을 따로 조절하세요. 체형은 오른쪽으로 갈수록 통통해요."
        }
    }

    private var partPicker: some View {
        Picker("편집할 부위", selection: $selection) {
            ForEach(OiSeedCucumberPart.allCases) { part in
                Text(part.title).tag(part)
            }
        }
        .accessibilityIdentifier("seedCucumber.part")
    }

    private func faceBinding(_ keyPath: WritableKeyPath<OiSeedCucumberAppearance.Face, CGFloat>) -> Binding<CGFloat> {
        let part = selection
        return Binding(get: { appearance[part][keyPath: keyPath] },
                       set: { appearance[part][keyPath: keyPath] = $0 })
    }

    private func slider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>,
                        display: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.subheadline)
            .accessibilityHidden(true)
            Slider(value: value, in: range) {
                Text(title)
            }
            .labelsHidden()
            .tint(Color("OiGreen"))
            .accessibilityValue(display)
            .accessibilityIdentifier("seedCucumber.\(id)")
        }
    }

    private func percent(_ value: CGFloat) -> String { "\(Int((value * 100).rounded()))%" }

    private func offsetLabel(_ value: CGFloat, negative: String, positive: String) -> String {
        let amount = Int(value.rounded())
        guard amount != 0 else { return "기본 위치" }
        return "\(amount < 0 ? negative : positive) \(abs(amount))"
    }
}

#Preview {
    NavigationStack {
        OiSeedCucumberCustomizationView()
    }
}
