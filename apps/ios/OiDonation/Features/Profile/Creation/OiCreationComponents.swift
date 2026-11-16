import MapKit
import SwiftUI

struct OiCreationProgressHeader: View {
    let step: Int
    var onPrevious: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    var canSelectStage: (Int) -> Bool = { _ in true }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectionFeedback = 0

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                                    GridItem(.flexible(), alignment: .top)], spacing: 12) {
                    ForEach(1...4, id: \.self) { number in stageButton(number, width: 66) }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { number in stageButton(number, width: 66) }
                }
            }
        }
        .foregroundStyle(Color("OiDark")).padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
    }

    private func stageButton(_ number: Int, width: CGFloat) -> some View {
        let isAllowed = canSelectStage(number)
        let canNavigate = isAllowed && (onSelect != nil || (number == step - 1 && onPrevious != nil))
        return Button {
            selectionFeedback += 1
            if let onSelect { onSelect(number) }
            else if number == step - 1 { onPrevious?() }
        } label: {
            VStack(spacing: 7) {
                OiCreationCurrentStepPulse(isCurrent: number == step, fitsLabel: dynamicTypeSize.isAccessibilitySize) {
                    ZStack {
                        stageFace(number, width: width).foregroundStyle(Color("OiDark")).offset(y: 4)
                        stageFace(number, width: width)
                            .foregroundStyle(LinearGradient(
                                colors: number == step
                                    ? [Color("OiGreen").opacity(0.85), Color("OiGreen")]
                                    : [Color("OiLight"), Color("OiBorder")],
                                startPoint: .top, endPoint: .bottom))
                            .shadow(color: .white.opacity(0.65), radius: 0.5, y: -1)
                    }
                } label: {
                    Text("STEP \(number)")
                        .font(.custom("Paperlogy-7Bold", size: 10, relativeTo: .caption2))
                        .foregroundStyle(number == step ? Color.white : Color("OiDark"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                }.frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 42)
                Text(title(number))
                    .font(.custom(number == step ? "Paperlogy-6SemiBold" : "Paperlogy-4Regular", size: 12, relativeTo: .caption))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
            .frame(maxWidth: .infinity, minHeight: 70).contentShape(Rectangle())
        }
        .buttonStyle(OiCreationFootprintStyle(selected: number == step))
        .disabled(!canNavigate)
        .opacity(!isAllowed && number != step ? 0.45 : 1)
        .accessibilityLabel("\(number)단계, \(title(number))")
        .accessibilityValue(number == step ? "현재 단계" : canNavigate ? "이동 가능" : "이동 불가")
        .accessibilityHint(canNavigate ? "입력한 내용을 유지하고 이 단계로 이동해요" : "")
        .accessibilityAddTraits(number == step ? .isSelected : [])
        .accessibilityIdentifier("oi.creation.stage.\(number)")
    }

    @ViewBuilder private func stageFace(_ number: Int, width: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Large text determines the badge size instead of overflowing fixed artwork.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
        } else {
            artwork(number, width: width)
        }
    }

    private func artwork(_ number: Int, width: CGFloat) -> some View {
        Image(number.isMultiple(of: 2) ? "ConsentStepInactiveLowered" : "ConsentStepActive")
            .resizable().renderingMode(.template)
            .frame(width: width, height: number.isMultiple(of: 2) ? width * 29.991 / 69.8566 : width * 38.4729 / 65.6168)
            .rotationEffect(.degrees(number.isMultiple(of: 2) ? 0 : 16.63))
    }

    private func title(_ number: Int) -> String {
        ["약관 동의", "이야기 작성", "오이 커스텀", "카드 커스텀"][number - 1]
    }
}

private extension EnvironmentValues {
    @Entry var oiCreationStepIsPressed = false
}

/// One phase drives brightness, size, lift and shadow; the text moves with the face.
private struct OiCreationCurrentStepPulse<Face: View, Label: View>: View {
    let isCurrent: Bool
    var fitsLabel = false
    @ViewBuilder var face: () -> Face
    @ViewBuilder var label: () -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.oiCreationStepIsPressed) private var isPressed

    var body: some View {
        if isCurrent && !reduceMotion && scenePhase == .active && !isPressed {
            PhaseAnimator([false, true]) { lowered in
                footprint(lowered: lowered)
            } animation: { _ in
                .easeInOut(duration: 1.6)
            }
        } else {
            footprint(lowered: false)
        }
    }

    private func footprint(lowered: Bool) -> some View {
        let closeToSurface = lowered || isPressed
        return Group {
            if fitsLabel {
                label()
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background { face().brightness(lowered ? -0.16 : 0) }
            } else {
                ZStack {
                    face().brightness(lowered ? -0.16 : 0)
                    label()
                }
            }
        }
        .scaleEffect(lowered ? 0.94 : 1)
        .rotation3DEffect(.degrees(lowered ? -5 : 0), axis: (x: 1, y: 0, z: 0))
        .offset(y: lowered ? 3 : 0)
        .shadow(color: Color("OiDark").opacity(closeToSurface ? 0.08 : 0.2),
                radius: closeToSurface ? 1 : 3, y: closeToSurface ? 1 : 4)
    }
}

private struct OiCreationFootprintStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.oiCreationStepIsPressed, configuration.isPressed)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.94 : selected ? 1.04 : 1)
            .rotation3DEffect(.degrees(reduceMotion || configuration.isPressed ? 0 : 7), axis: (x: 1, y: 0, z: 0))
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 3 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.58), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.65), value: selected)
    }
}

/// A tactile response without changing the footprint artwork or repeating motion.
struct OiCreationPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .offset(y: configuration.isPressed && !reduceMotion ? 2 : 0)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Keep clearance independent of visibility so showing the panel cannot change
// the scroll end and repeatedly hide/show it.
extension EnvironmentValues {
    @Entry var oiCreationNavigationClearance: CGFloat = 0
    @Entry var oiCustomizationBottomInset: CGFloat = 0
}

struct OiCreationScrollNavigation: ViewModifier {
    @Environment(\.oiCreationNavigationClearance) private var clearance
    let onVisibilityChange: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, clearance)
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                CGSize(width: geometry.contentOffset.y,
                       height: max(-geometry.contentInsets.top,
                           geometry.contentSize.height - geometry.containerSize.height))
            } action: { _, position in
                onVisibilityChange(position.width >= position.height - 8)
            }
            .onDisappear { onVisibilityChange(false) }
    }
}

enum OiCustomizationStyle {
    static let previewUIColor = UIColor(wardrobeRGB: 0xF5F6F2)
    static let previewBackground = Color(uiColor: previewUIColor)
}

struct OiCustomizationPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
        content
            .background(.white)
            .clipShape(shape)
            .background {
                shape.fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: -3)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
    }
}

/// Only the scrolled settings fade under the fixed tabs; the preview stays crisp.
struct OiCustomizationScrollEdge: ViewModifier {
    @State private var hasScrolled = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > -geometry.contentInsets.top + 1
            } action: { _, scrolled in hasScrolled = scrolled }
            .overlay(alignment: .top) {
                if hasScrolled {
                    if reduceTransparency {
                        Color.black.opacity(0.08).frame(height: 1)
                    } else {
                        LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 16).allowsHitTesting(false)
                    }
                }
            }
    }
}

struct OiCreationNavigationBar: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var canContinue = true
    /// STEP 2 (Figma `5400:7726` 하단 버튼): placed at the end of the scrolled content without a panel.
    var inline = false
    /// Required items still missing after Next was tapped on the story step, shown under the buttons (#373).
    var missingItems: [String] = []
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSaveAndExit: () -> Void
    var body: some View {
        VStack(spacing: inline ? 0 : 8) {
            Button("임시저장 후 나가기", action: onSaveAndExit)
                .font(CampusStyle.body(14)).underline()
                .foregroundStyle(inline ? Color(white: 64 / 255) : .secondary)
                // Inline: Figma `5919:11738` leaves 12pt from the underline to the buttons; the 44pt hit area overlaps it.
                .frame(minHeight: 44).contentShape(Rectangle())
                .padding(.top, inline ? -9 : 0).padding(.bottom, inline ? -3 : 0)
                .accessibilityIdentifier("oi.creation.saveAndExit")
            HStack(spacing: 12) {
                navigationButton("이전", tint: inline ? Color(oiRGB: 0xB6C59B) : Color("OiBorder"), action: onPrevious)
                    .accessibilityIdentifier("oi.creation.previous")
                navigationButton("다음", tint: Color("OiGreen"), action: onNext)
                    .disabled(!canContinue).opacity(canContinue ? 1 : 0.45)
                    .accessibilityIdentifier("oi.creation.next")
            }
            if !missingItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(missingItems, id: \.self) { Text($0) }
                }
                .font(CampusStyle.body(15))
                .foregroundStyle(Color(red: 1, green: 56 / 255, blue: 60 / 255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("oi.creation.missingItems")
            }
        }
        .padding(.horizontal, inline ? 0 : 20).padding(.bottom, inline ? 0 : 10)
        .background {
            if !inline { navigationBackground.ignoresSafeArea(.container, edges: .bottom) }
        }
    }
    @ViewBuilder private var navigationBackground: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)
        if reduceTransparency {
            shape.fill(Color(.systemBackground))
        } else if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
    private func navigationButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(CampusStyle.medium(16)).tracking(title == "이전" && inline ? 0.32 : 0)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(tint, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(OiCreationPressStyle())
            .foregroundStyle(title == "이전" && !inline ? Color("OiDark") : .white)
    }
}

struct OiCreationNextButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.custom("Paperlogy-5Medium", size: 17, relativeTo: .body))
                .frame(maxWidth: .infinity, minHeight: 57)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 20))
        .tint(Color("OiGreen")).disabled(!enabled)
    }
}

struct OiCreationDoneButton: View {
    var enabled = true
    var title = "완료"
    let action: () -> Void
    var body: some View {
        // Figma `5719:9874`: 16pt black on #D3DBC4, 16×6 padding, inside a 44pt hit area.
        Button(action: action) {
            Text(title).font(CampusStyle.body(16)).tracking(0.32)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color("OiBorder"), in: Capsule())
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(OiCreationPressStyle()).foregroundStyle(.black).disabled(!enabled)
    }
}

struct OiCreationSection<Content: View>: View {
    let title: String
    var hint: String = ""
    var titleSize: CGFloat = 26
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let headingLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .bottom, spacing: 10))
            headingLayout {
                Text(title).font(.custom("Paperlogy-6SemiBold", size: titleSize, relativeTo: .title2))
                if !hint.isEmpty {
                    Text(hint).font(.custom("Paperlogy-3Light", size: 16, relativeTo: .subheadline))
                        .tracking(0.32).foregroundStyle(Color("OiGreen"))
                }
            }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OiStoryWritingStep: View {
    enum Field: Hashable { case title, body }

    @Binding var draft: OiStoryDraft
    @Binding var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let fieldBackground = Color(white: 244 / 255)
    static let themes = ["가족", "우정", "사랑", "성장", "도전", "꿈", "배움", "경쟁", "협력", "갈등", "화해", "일탈", "나눔", "응원", "성취", "기타"]
    static let emotions = ["행복함", "즐거움", "뿌듯함", "고마움", "편안함", "설렘", "따뜻함", "짜릿함", "놀라움", "신남", "벅참", "그리움", "후련함", "부끄러움", "후회", "긴장감", "슬픔", "화남", "아쉬움", "기타"]
    var body: some View {
        VStack(alignment: .leading, spacing: 50) {
            OiCreationSection(title: "테마 선택", hint: "(택 1)") { tags(Self.themes, selected: $draft.theme) }
            OiCreationSection(title: "감정 선택", hint: "(택 1)") { tags(Self.emotions, selected: $draft.emotion) }
            OiCreationSection(title: "제목 입력", hint: "(띄어쓰기 포함 \(OiCreationStep.storyTitleByteLimit)byte 이내)") {
                inputBox($draft.title, field: .title, limit: OiCreationStep.storyTitleByteLimit,
                         label: "이야기 제목", identifier: "oi.draft.title")
            }
            OiCreationSection(title: "이야기 입력", hint: "(띄어쓰기 포함 \(OiCreationStep.storyBodyByteLimit)byte 이내)") {
                inputBox($draft.body, field: .body, limit: OiCreationStep.storyBodyByteLimit,
                         label: "이야기 내용", identifier: "oi.draft.body")
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
        .padding(.top, 20)
    }

    static func limitedText(_ text: Binding<String>) -> Binding<String> {
        limited(text, byteLimit: OiCreationStep.storyTitleByteLimit)
    }

    static func limitedStoryText(_ text: Binding<String>) -> Binding<String> {
        limited(text, byteLimit: OiCreationStep.storyBodyByteLimit)
    }

    private static func limited(_ text: Binding<String>, byteLimit: Int) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { value in
            text.wrappedValue = OiCreationStep.limitedEdit(value, previous: text.wrappedValue, byteLimit: byteLimit)
        })
    }

    private func inputBox(_ text: Binding<String>, field: Field, limit: Int, label: String, identifier: String) -> some View {
        let editorInset = EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)
        return HStack(alignment: .center) {
            // UIKit applies the byte limit after Korean composition so rejected text never stays on screen.
            OiStoryTextView(text: text, focusedField: $focusedField, field: field, byteLimit: limit,
                            label: label, identifier: identifier)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("입력").foregroundStyle(Color(uiColor: .placeholderText))
                            .font(.custom("Paperlogy-3Light", size: 18, relativeTo: .body))
                            .tracking(0.36)
                            .padding(editorInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            Image(systemName: "pencil")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color(white: 106 / 255))
                .accessibilityHidden(true)
        }
        .padding(.leading, 15)
        .padding(.trailing, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(fieldBackground, in: RoundedRectangle(cornerRadius: 15))
    }

    private func tags(_ values: [String], selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                OiCreationTagLayout {
                    ForEach(values, id: \.self) { tag($0, selected: selected) }
                }
            } else {
                // A 36pt chip inside a 44pt hit area leaves 4pt above and below.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(stride(from: 0, to: values.count, by: 4)), id: \.self) { start in
                        HStack(spacing: 10) {
                            ForEach(values[start..<min(start + 4, values.count)], id: \.self) {
                                tag($0, selected: selected)
                            }
                        }
                    }
                }
            }
            if !selected.wrappedValue.isEmpty && !values.contains(selected.wrappedValue) {
                Text("기존 선택: \(selected.wrappedValue)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tag(_ value: String, selected: Binding<String>) -> some View {
        let isSelected = selected.wrappedValue == value
        return Button {
            selected.wrappedValue = value
        } label: {
            Text(value)
                .tracking(0.32).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 20).frame(minHeight: 36)
                .foregroundStyle(isSelected ? Color.white : Color("OiDark"))
                .background(isSelected ? Color("OiGreen") : fieldBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color("OiGreen") : Color(white: 234 / 255), lineWidth: 1))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Photo and location editors are opened from the story form, as in Figma 2945:2931.
struct OiStoryAttachmentSections: View {
    let photoCount: Int
    let latitude: Double?
    let longitude: Double?
    let onPhotos: () -> Void
    let onLocation: () -> Void

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(value) ? value : nil
    }

    var body: some View {
        // Figma `5400:7726`: the photo comes before the location, whose title is 30pt.
        VStack(alignment: .leading, spacing: 50) {
            OiCreationSection(title: "사진 선택", hint: "(\(OiCreationStep.storyPhotoLimit)장)") {
                formButton(photoCount == 0 ? "사진 추가하기" : "선택한 사진 보기",
                           highlighted: false, action: onPhotos)
                    .accessibilityIdentifier("oi.story.editPhotos")
            }
            OiCreationSection(title: "오이 위치 설정", titleSize: 30) {
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: coordinate ?? CLLocationCoordinate2D(latitude: 36.0139, longitude: 129.3232),
                    latitudinalMeters: coordinate == nil ? 1_200 : 300,
                    longitudinalMeters: coordinate == nil ? 1_200 : 300))), interactionModes: []) {
                    if let coordinate { Marker("선택한 오이 위치", coordinate: coordinate).tint(.red) }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 245).clipShape(RoundedRectangle(cornerRadius: 20))
                .allowsHitTesting(false)
                .overlay(alignment: .bottom) {
                    if coordinate == nil {
                        Text("아래 버튼에서 위치를 선택해 주세요")
                            .font(CampusStyle.body(14)).padding(12)
                            .background(.regularMaterial, in: Capsule()).padding(12)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(coordinate == nil ? "위치를 선택하지 않은 캠퍼스 지도" : "선택한 오이 위치 지도")
                .accessibilityIdentifier("oi.story.locationPreview")
                formButton(coordinate == nil ? "위치 설정하기" : "재설정하기", highlighted: true, action: onLocation)
                    .accessibilityIdentifier("oi.story.editLocation")
            }
        }
    }

    private func formButton(_ title: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(CampusStyle.medium(17)).tracking(0.34)
                .frame(maxWidth: .infinity, minHeight: 57)
                .foregroundStyle(highlighted ? Color("OiGreen") : Color(white: 106 / 255))
                .background(highlighted ? Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255) : Color(white: 244 / 255),
                            in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(OiCreationPressStyle())
    }
}

/// Wraps intrinsic chip widths while keeping the Figma ten-point horizontal gap.
private struct OiCreationTagLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 362
        return arrange(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, point) in arrangement.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                                 proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: min(subview.sizeThatFits(.unspecified).width, width), height: nil))
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + 2; rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + 10; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

/// Self-sizing story field. The byte limit is checked only after Korean composition ends;
/// SwiftUI `TextEditor` keeps showing composed text that its binding rejected (#373).
struct OiStoryTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focusedField: OiStoryWritingStep.Field?
    let field: OiStoryWritingStep.Field
    let byteLimit: Int
    let label: String
    let identifier: String

    private static var attributes: [NSAttributedString.Key: Any] {
        let base = UIFont(name: "Paperlogy-3Light", size: 18) ?? .systemFont(ofSize: 18, weight: .light)
        return [.font: UIFontMetrics(forTextStyle: .body).scaledFont(for: base), .kern: 0.36, .foregroundColor: UIColor.label]
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 5
        view.typingAttributes = Self.attributes
        view.attributedText = NSAttributedString(string: text, attributes: Self.attributes)
        view.delegate = context.coordinator
        view.accessibilityLabel = label
        view.accessibilityIdentifier = identifier
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else { return nil }
        return CGSize(width: width, height: uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.markedTextRange == nil, view.text != text {
            view.attributedText = NSAttributedString(string: text, attributes: Self.attributes)
        }
        if focusedField == field, !view.isFirstResponder, view.window != nil {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if focusedField != field, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: OiStoryTextView
        init(_ parent: OiStoryTextView) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            // Wait until a Korean syllable is committed before counting it.
            guard view.markedTextRange == nil else { return }
            let value = view.text ?? ""
            let accepted = OiCreationStep.limitedEdit(value, previous: parent.text, byteLimit: parent.byteLimit)
            if accepted != value {
                let removed = (value as NSString).length - (accepted as NSString).length
                let caret = max(0, view.selectedRange.location - removed)
                view.attributedText = NSAttributedString(string: accepted, attributes: OiStoryTextView.attributes)
                view.selectedRange = NSRange(location: min(caret, (accepted as NSString).length), length: 0)
            }
            if parent.text != accepted { parent.text = accepted }
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            let field = parent.field
            if parent.focusedField != field { DispatchQueue.main.async { self.parent.focusedField = field } }
        }

        func textViewDidEndEditing(_ view: UITextView) {
            textViewDidChange(view)
            let field = parent.field
            if parent.focusedField == field { DispatchQueue.main.async { self.parent.focusedField = nil } }
        }
    }
}
