import SwiftUI
import UIKit

struct OiDraftCardPreview: View {
    let draft: OiStoryDraft
    let customization: OiDraftCustomization
    var donorName = ""
    var portrait: UIImage? = nil
    private var design: OiCardDesign { customization.card ?? OiCardDesign() }
    var body: some View {
        GeometryReader { proxy in
            composition.frame(width: 362, height: 502)
                .scaleEffect(proxy.size.width / 362, anchor: .topLeading)
        }.aspectRatio(362 / 502, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("카드 미리보기, \(draft.cucumberName), \(design.caption ?? draft.title)")
    }
    private var cardCaption: String {
        if let caption = design.caption, !caption.isEmpty { return caption }
        return draft.title.isEmpty ? "오래 남는 나의 이야기" : draft.title
    }
    private var composition: some View {
        ZStack(alignment: .topLeading) {
            OiCardGradient(fill: design.borderFill, first: design.borderFirst, second: design.borderSecond)
            ZStack(alignment: .topLeading) {
                OiCardGradient(fill: customization.fill, first: customization.firstColor, second: customization.secondColor)
                if let bytes = design.backgroundPhoto, let photo = UIImage(data: bytes) {
                    OiCardPlacedImage(image: photo, placement: design.backgroundPlacement)
                }
                if let pattern = design.pattern {
                    Image("OiCardPattern\(pattern)").resizable().scaledToFill()
                        .frame(width: 332, height: 472).blendMode(.softLight).opacity(0.65)
                }
                if customization.showsCharacter {
                    if let portrait {
                        OiCardPlacedImage(image: portrait, placement: design.characterPlacement)
                    } else if let bytes = design.portraitPNG, let image = UIImage(data: bytes) {
                        OiCardPlacedImage(image: image, placement: design.characterPlacement)
                    } else {
                        OiCreationCharacterImage(asset: draft.cucumberAsset)
                            .frame(width: 332, height: 472)
                    }
                }
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    Spacer()
                    Text(cardCaption)
                        .font(.custom("PearToucan-Regular", size: 17)).lineSpacing(3).lineLimit(3)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    HStack(spacing: 5) {
                        ForEach(Array([draft.theme, draft.emotion].filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, tag in
                            Text(tag).font(CampusStyle.body(10)).padding(.horizontal, 9).padding(.vertical, 3)
                                .background(.white, in: Capsule())
                        }
                    }
                    HStack {
                        Image("OiStoryCardMark").resizable().scaledToFit().frame(width: 16, height: 16)
                            .padding(3).background(Color("OiLight"), in: RoundedRectangle(cornerRadius: 4))
                        Spacer()
                        Text(design.anonymous ? "익명" : donorName).font(CampusStyle.body(10)).lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "wave.3.right").font(.system(size: 20)).foregroundStyle(.white)
                    }
                }.padding(14).frame(width: 332, height: 472)
                Image("OiStoryCardHeader").resizable().frame(width: 268, height: 36)
                Image("OiStoryCardFrame").resizable().frame(width: 332, height: 472)
                Text("NORMAL").font(.custom("PearToucan-Bold", size: 11))
                    .foregroundStyle(Color(white: 0.45)).frame(width: 64, height: 36)
                Text(draft.cucumberName.isEmpty ? "나의 오이" : draft.cucumberName)
                    .font(.custom("PearToucan-Light", size: 21)).lineLimit(1).minimumScaleFactor(0.55)
                    .frame(width: 184, height: 36, alignment: .leading).offset(x: 77)
            }.frame(width: 332, height: 472).clipShape(RoundedRectangle(cornerRadius: 9)).offset(x: 15, y: 15)
        }.clipShape(RoundedRectangle(cornerRadius: 15)).dynamicTypeSize(.medium)
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
            HStack(alignment: .top) {
                Text(look == nil ? title : "한 손가락으로 이동 · 핀치로 크기 조절\n두 손가락을 함께 드래그해 3D 회전")
                    .font(CampusStyle.body(10)).foregroundStyle(Color("OiGreen"))
                Spacer()
                Button("초기화") {
                    placement = OiCardPlacement()
                    orientation?.wrappedValue = OiCardOrientation()
                    onInteractionEnded?()
                }.font(CampusStyle.body(12)).tint(Color("OiGreen"))
                    .accessibilityIdentifier("oi.card.placement.reset")
            }
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
            }.frame(width: frameHeight * 332 / 472, height: frameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(look == nil ? "카드 이미지 위치와 크기" : "오이 3D 방향과 카드 위치, 크기")
                .accessibilityValue("\(Int(placement.normalized.scale * 100))퍼센트")
                .accessibilityAdjustableAction { direction in
                    placement.scale += direction == .increment ? 0.1 : -0.1
                    placement = placement.normalized
                }
                .accessibilityAction(named: "위로 이동") { placement.y -= 0.05; placement = placement.normalized }
                .accessibilityAction(named: "아래로 이동") { placement.y += 0.05; placement = placement.normalized }
                .accessibilityAction(named: "왼쪽으로 이동") { placement.x -= 0.05; placement = placement.normalized }
                .accessibilityAction(named: "오른쪽으로 이동") { placement.x += 0.05; placement = placement.normalized }
            if portraitFailed {
                Button("오이 이미지 다시 불러오기") { portraitFailed = false; renderAttempt += 1 }
                    .font(.caption).tint(Color("OiGreen"))
            }
            if let orientation {
                HStack(spacing: 12) {
                    angleButton("왼쪽 회전", symbol: "rotate.left", dx: -25, dy: 0, orientation: orientation)
                    angleButton("오른쪽 회전", symbol: "rotate.right", dx: 25, dy: 0, orientation: orientation)
                    angleButton("위에서 보기", symbol: "arrow.up", dx: 0, dy: 15, orientation: orientation)
                    angleButton("아래에서 보기", symbol: "arrow.down", dx: 0, dy: -15, orientation: orientation)
                }
                Text("손을 놓으면 카드에 같은 각도로 반영돼요.")
                    .font(CampusStyle.body(10)).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity)
            .background(Color("OiBorder").opacity(0.75))
    }
    private func angleButton(_ label: String, symbol: String, dx: Double, dy: Double,
                             orientation: Binding<OiCardOrientation>) -> some View {
        Button {
            orientation.wrappedValue = orientation.wrappedValue.rotated(horizontal: dx, vertical: dy)
            onInteractionEnded?()
        } label: { Image(systemName: symbol).frame(width: 44, height: 44) }
            .buttonStyle(.plain).tint(Color("OiGreen")).accessibilityLabel(label)
    }
}

/// UIKit keeps pinch and pan simultaneous and prevents the surrounding controls
/// from scrolling while the user is intentionally moving the framed image.
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
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let orbit = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.orbit(_:)))
        orbit.minimumNumberOfTouches = 2; orbit.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        for gesture in [pan, orbit, pinch] {
            gesture.delegate = context.coordinator; view.addGestureRecognizer(gesture)
        }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.placement = $placement
        context.coordinator.orientation = orientation
        context.coordinator.onInteractionEnded = onInteractionEnded
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var placement: Binding<OiCardPlacement>
        var orientation: Binding<OiCardOrientation>?
        var onInteractionEnded: (() -> Void)?
        init(placement: Binding<OiCardPlacement>, orientation: Binding<OiCardOrientation>?, onInteractionEnded: (() -> Void)?) {
            self.placement = placement; self.orientation = orientation; self.onInteractionEnded = onInteractionEnded
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gesture.view === other.view
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            defer { gesture.setTranslation(.zero, in: gesture.view) }
            guard gesture.numberOfTouches == 1, gesture.state == .began || gesture.state == .changed,
                  let view = gesture.view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let delta = gesture.translation(in: view)
            var p = placement.wrappedValue
            p.x += delta.x / view.bounds.width; p.y += delta.y / view.bounds.height
            placement.wrappedValue = p.normalized
        }
        @objc func orbit(_ gesture: UIPanGestureRecognizer) {
            defer { gesture.setTranslation(.zero, in: gesture.view) }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                onInteractionEnded?(); return
            }
            guard gesture.numberOfTouches == 2, gesture.state == .began || gesture.state == .changed else { return }
            let delta = gesture.translation(in: gesture.view)
            if let orientation {
                orientation.wrappedValue = orientation.wrappedValue.rotated(horizontal: delta.x, vertical: delta.y)
            } else if let view = gesture.view, view.bounds.width > 0, view.bounds.height > 0 {
                // Background photos still translate with two fingers while pinching.
                var p = placement.wrappedValue
                p.x += delta.x / view.bounds.width; p.y += delta.y / view.bounds.height
                placement.wrappedValue = p.normalized
            }
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            var p = placement.wrappedValue; p.scale *= gesture.scale
            placement.wrappedValue = p.normalized; gesture.scale = 1
        }
    }
}
