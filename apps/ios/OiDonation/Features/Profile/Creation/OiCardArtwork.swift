import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct OiDraftCardPreview: View {
    let draft: OiStoryDraft
    let customization: OiDraftCustomization
    var donorName = ""
    var portrait: UIImage? = nil
    var showingBack = false
    private var design: OiCardDesign { customization.card ?? OiCardDesign() }
    var body: some View {
        GeometryReader { proxy in
            Group {
                if showingBack {
                    OiPostcardBack(fill: design.borderFill, first: design.borderFirst, second: design.borderSecond,
                        backgroundStyle: design.postcardBackground, message: draft.body, author: donorName)
                } else { composition }
            }.frame(width: 362, height: 502)
                .scaleEffect(proxy.size.width / 362, anchor: .topLeading)
        }.aspectRatio(362 / 502, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("엽서 \(showingBack ? "뒷면" : "앞면") 미리보기, \(draft.cucumberName)")
    }

    @MainActor func publication(colorScheme: ColorScheme) throws -> OiStoryCardPublication {
        let renderer = ImageRenderer(content: composition.frame(width: 362, height: 502)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = 2
        guard let image = renderer.uiImage else { throw OiPhotoDataError.unreadable }
        let png = design.postcardBackground.flatMap { OiPostcardBackgroundMetadata.png(image: image, style: $0) } ?? image.pngData()
        guard let png else { throw OiPhotoDataError.unreadable }
        return try OiStoryCardPublication(png: png)
    }
    private var composition: some View {
        OiPostcardFront(fill: design.borderFill, first: design.borderFirst, second: design.borderSecond,
                        backgroundStyle: design.postcardBackground, date: OiPostcardDate.string(design.postcardDate ?? Date())) {
            ZStack {
                OiCardBackground(customization: customization, pattern: design.pattern)
                if customization.showsCharacter {
                    if let image = portrait ?? design.portraitPNG.flatMap(UIImage.init(data:)) {
                        OiCardPlacedImage(image: image, placement: design.characterPlacement)
                    } else {
                        OiCreationCharacterImage(asset: draft.cucumberAsset)
                    }
                }
            }
        }
    }
}


/// Shared by the card and its pattern swatches so a selection previews the actual
/// background color/photo. Isolate blending from the portrait, text and border.
struct OiCardBackground: View {
    let customization: OiDraftCustomization
    let pattern: Int?
    var gradientInset: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            let paper = customization.card ?? OiCardDesign()
            let photoTint = paper.photoMonochrome == true && paper.backgroundPhoto != nil
            ZStack {
                Group {
                    if let style = paper.postcardBackground {
                        // Crop the very same full-paper background into the artwork window.
                        OiPostcardBackground(style: style)
                            .frame(width: geometry.size.width * 362 / 296, height: geometry.size.height * 502 / 436)
                    } else {
                        OiCardGradient(fill: photoTint ? paper.borderFill : customization.fill,
                                       first: photoTint ? paper.borderFirst : customization.firstColor,
                                       second: photoTint ? paper.borderSecond : customization.secondColor)
                            .frame(width: geometry.size.width + gradientInset * 2,
                                   height: geometry.size.height + gradientInset * 2)
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                if let design = customization.card, let bytes = design.backgroundPhoto,
                   let photo = UIImage(data: bytes) {
                    OiCardPlacedImage(image: photo, placement: design.backgroundPlacement)
                        .saturation(design.photoMonochrome == true ? 0 : 1)
                        .blendMode(design.photoMonochrome == true ? .luminosity : .normal)
                }
                if let pattern, let image = OiCardPatternTexture.image(for: pattern) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blendMode(.luminosity).opacity(0.62)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .clipped().compositingGroup()
        }.allowsHitTesting(false)
    }
}

struct OiCardGradient: View {
    var fill: OiDraftCustomization.Fill
    var first: UInt32
    var second: UInt32
    var body: some View {
        LinearGradient(colors: [Color(oiRGB: first), Color(oiRGB: fill == .solid ? first : second)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The exact same normalized transform is used for editing and final card drawing.
struct OiCardPlacedImage: View {
    let image: UIImage
    let placement: OiCardPlacement
    var body: some View {
        GeometryReader { proxy in
            let p = placement.normalized
            Image(uiImage: image).resizable().scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(p.scale)
                .offset(x: (p.x - 0.5) * proxy.size.width, y: (p.y - 0.5) * proxy.size.height)
        }.clipped().allowsHitTesting(false)
    }
}

struct OiCardPlacementEditor: View {
    let image: UIImage?
    @Binding var placement: OiCardPlacement
    var title = "캐릭터를 눌러 선택한 뒤\n드래그·핀치로 배치하세요."
    var frameHeight: CGFloat = 232.3
    var compact = false
    var emptyMessage = "오이 이미지를 준비하고 있어요"
    var look: OiWardrobeLook? = nil
    var orientation: Binding<OiCardOrientation>? = nil
    var portraitKey = ""
    var onCapture: ((Data, String) -> Void)? = nil
    var onInteractionEnded: (() -> Void)? = nil
    @State private var renderAttempt = 0
    @State private var portraitFailed = false
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if orientation != nil {
                    Label("360°", systemImage: "rotate.3d")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color("OiGreen"))
                        .accessibilityLabel("두 손가락 드래그로 3D 회전")
                } else {
                    Text(title).font(CampusStyle.body(10)).foregroundStyle(Color("OiGreen"))
                }
                Spacer(minLength: 0)
                if compact {
                    Text("이동 · 회전 · 핀치")
                        .font(CampusStyle.body(11)).foregroundStyle(.secondary)
                }
                Button("초기화") {
                    placement = OiCardPlacement()
                    orientation?.wrappedValue = OiCardOrientation()
                    onInteractionEnded?()
                }.font(CampusStyle.body(12)).tint(Color("OiGreen"))
                    .frame(minWidth: 44, minHeight: compact ? 32 : 24)
                    .accessibilityIdentifier("oi.card.placement.reset")
            }.frame(height: compact ? 32 : nil)
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(.white)
                if let look, let orientation, let onCapture {
                    GeometryReader { proxy in
                        let p = placement.normalized
                        OiCardPortraitCapture(look: look, cacheKey: portraitKey,
                            orientation: orientation.wrappedValue, interactivePreview: true,
                            onCapture: { data, key in portraitFailed = false; onCapture(data, key) },
                            onFailure: { portraitFailed = true })
                            .id(renderAttempt)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(p.scale)
                            .offset(x: (p.x - 0.5) * proxy.size.width, y: (p.y - 0.5) * proxy.size.height)
                    }.clipped()
                } else if let image { OiCardPlacedImage(image: image, placement: placement) }
                else { Text(emptyMessage).font(CampusStyle.body(11)).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(12) }
                RoundedRectangle(cornerRadius: 5).stroke(Color("OiGreen"), lineWidth: 1)
                OiCardPlacementGestures(placement: $placement, orientation: orientation,
                                        onInteractionEnded: onInteractionEnded)
            }.frame(width: frameHeight * 296 / 436, height: frameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(look == nil ? "카드 이미지 위치와 크기" : "오이 3D 방향과 카드 위치, 크기")
                .accessibilityValue("\(Int(placement.normalized.scale * 100))퍼센트")
                .accessibilityHint(orientation == nil ? "드래그로 이동, 핀치로 크기 조절" : "한 손가락으로 이동, 두 손가락 드래그로 회전, 핀치로 크기 조절")
                .accessibilityActions {
                    if let orientation {
                        Button("왼쪽 회전") { rotate(orientation, dx: -25, dy: 0) }
                        Button("오른쪽 회전") { rotate(orientation, dx: 25, dy: 0) }
                        Button("위에서 보기") { rotate(orientation, dx: 0, dy: 15) }
                        Button("아래에서 보기") { rotate(orientation, dx: 0, dy: -15) }
                    }
                }
                .accessibilityAdjustableAction { direction in
                    placement.scale += direction == .increment ? 0.1 : -0.1
                    placement = placement.normalized
                }
                .accessibilityAction(named: "위로 이동") { placement.y -= 0.05; placement = placement.normalized }
                .accessibilityAction(named: "아래로 이동") { placement.y += 0.05; placement = placement.normalized }
                .accessibilityAction(named: "왼쪽으로 이동") { placement.x -= 0.05; placement = placement.normalized }
                .accessibilityAction(named: "오른쪽으로 이동") { placement.x += 0.05; placement = placement.normalized }
        }.padding(.horizontal, 20).padding(.vertical, compact ? 8 : 20)
            .frame(maxWidth: .infinity)
            .background(compact ? Color.clear : Color("OiBorder").opacity(0.75))
            .overlay(alignment: .bottom) {
                if portraitFailed {
                    Button("오이 다시 불러오기") { portraitFailed = false; renderAttempt += 1 }
                        .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
                        .tint(Color("OiGreen")).padding(.bottom, 12)
                }
            }
    }
    private func rotate(_ orientation: Binding<OiCardOrientation>, dx: Double, dy: Double) {
        orientation.wrappedValue = orientation.wrappedValue.rotated(horizontal: dx, vertical: dy)
        onInteractionEnded?()
    }
}

/// A single recognizer owns each complete touch sequence. It avoids pan/pinch
/// recognizers independently translating when a second finger lands or lifts.
private struct OiCardPlacementGestures: UIViewRepresentable {
    @Binding var placement: OiCardPlacement
    var orientation: Binding<OiCardOrientation>?
    var onInteractionEnded: (() -> Void)?
    func makeCoordinator() -> Coordinator {
        Coordinator(placement: $placement, orientation: orientation, onInteractionEnded: onInteractionEnded)
    }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear; view.isMultipleTouchEnabled = true
        view.accessibilityIdentifier = "oi.card.placement.canvas"
        view.addGestureRecognizer(OiTouchSequenceRecognizer(target: context.coordinator,
                                                       action: #selector(Coordinator.update(_:))))
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.placement = $placement
        context.coordinator.orientation = orientation
        context.coordinator.onInteractionEnded = onInteractionEnded
    }
    final class Coordinator: NSObject {
        var placement: Binding<OiCardPlacement>
        var orientation: Binding<OiCardOrientation>?
        var onInteractionEnded: (() -> Void)?
        private var session = OiCardGestureState()
        init(placement: Binding<OiCardPlacement>, orientation: Binding<OiCardOrientation>?, onInteractionEnded: (() -> Void)?) {
            self.placement = placement; self.orientation = orientation; self.onInteractionEnded = onInteractionEnded
        }
        @objc func update(_ gesture: OiTouchSequenceRecognizer) {
            guard let view = gesture.view else { return }
            var p = placement.wrappedValue
            var angle = orientation?.wrappedValue
            session.update(points: gesture.points, bounds: view.bounds.size, placement: &p, orientation: &angle)
            if p != placement.wrappedValue { placement.wrappedValue = p }
            if let angle, angle != orientation?.wrappedValue { orientation?.wrappedValue = angle }
            if gesture.state == .ended || gesture.state == .cancelled { onInteractionEnded?() }
        }
    }
}

final class OiTouchSequenceRecognizer: UIGestureRecognizer {
    private var active: [UITouch: Int] = [:]
    private var nextID = 0
    var points: [Int: CGPoint] {
        Dictionary(uniqueKeysWithValues: active.map { ($0.value, $0.key.location(in: view)) })
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { active[touch] = nextID; nextID += 1 }
        state = state == .possible ? .began : .changed
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { active.removeValue(forKey: touch) }
        state = active.isEmpty ? .ended : .changed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        active.removeAll(); state = .cancelled
    }
    override func reset() { super.reset(); active.removeAll(); nextID = 0 }
}
