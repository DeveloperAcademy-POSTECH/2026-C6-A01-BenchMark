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

struct OiCreationNavigationBar: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var canContinue = true
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSaveAndExit: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Button("임시저장 후 나가기", action: onSaveAndExit)
                .font(CampusStyle.body(14)).underline()
                .foregroundStyle(.secondary).frame(minHeight: 44)
                .accessibilityIdentifier("oi.creation.saveAndExit")
            HStack(spacing: 12) {
                navigationButton("이전", tint: Color("OiBorder"), action: onPrevious)
                    .accessibilityIdentifier("oi.creation.previous")
                navigationButton("다음", tint: Color("OiGreen"), action: onNext)
                    .disabled(!canContinue).opacity(canContinue ? 1 : 0.45)
                    .accessibilityIdentifier("oi.creation.next")
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
        .background {
            navigationBackground.ignoresSafeArea(.container, edges: .bottom)
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
            Text(title).font(CampusStyle.medium(16)).frame(maxWidth: .infinity, minHeight: 46)
                .background(tint, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(OiCreationPressStyle())
            .foregroundStyle(title == "이전" ? Color("OiDark") : .white)
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
        Button(action: action) {
            Text(title).font(CampusStyle.medium(20)).tracking(0.4)
                .padding(.horizontal, 20).frame(minHeight: 44)
                .background(Color("OiBorder"), in: Capsule())
        }.buttonStyle(OiCreationPressStyle()).foregroundStyle(Color("OiGreen")).disabled(!enabled)
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
    let focusedField: FocusState<Field?>.Binding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let fieldBackground = Color(white: 244 / 255)
    private let textLimit = OiCreationStep.storyTextLimit
    static let themes = ["가족", "우정", "사랑", "성장", "도전", "꿈", "배움", "경쟁", "협력", "갈등", "화해", "일탈", "나눔", "응원", "성취", "기타"]
    static let emotions = ["행복함", "즐거움", "뿌듯함", "고마움", "편안함", "설렘", "따뜻함", "짜릿함", "놀라움", "신남", "벅참", "그리움", "후련함", "부끄러움", "후회", "긴장감", "슬픔", "화남", "아쉬움", "기타"]
    var body: some View {
        VStack(alignment: .leading, spacing: 50) {
            OiCreationSection(title: "테마 선택", hint: "(택 1)") { tags(Self.themes, selected: $draft.theme) }
            OiCreationSection(title: "감정 선택", hint: "(택 1)") { tags(Self.emotions, selected: $draft.emotion) }
            OiCreationSection(title: "제목 입력", hint: "(띄어쓰기 포함 \(textLimit)자 이내)") {
                inputBox($draft.title, field: .title, label: "이야기 제목", identifier: "oi.draft.title")
            }
            OiCreationSection(title: "이야기 입력", hint: "(띄어쓰기 포함 1,500byte 이내)") {
                inputBox($draft.body, field: .body, label: "이야기 내용", identifier: "oi.draft.body")
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
        .padding(.top, 20)
    }

    static func limitedText(_ text: Binding<String>) -> Binding<String> {
        let textLimit = OiCreationStep.storyTextLimit
        return Binding(get: { text.wrappedValue }, set: { newValue in
            let previousCount = text.wrappedValue.count
            let newCount = newValue.count
            // Keep longer drafts intact on restore and let the author shorten them.
            let isShorteningLongDraft = previousCount > textLimit && newCount < previousCount
            guard newCount <= textLimit || isShorteningLongDraft else { return }
            text.wrappedValue = newValue
        })
    }

    static func limitedStoryText(_ text: Binding<String>) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { value in
            let previousBytes = text.wrappedValue.utf8.count
            let bytes = value.utf8.count
            // Restore old stories without truncation; allow shortening an over-limit draft.
            guard bytes <= OiCreationStep.storyBodyByteLimit ||
                    (previousBytes > OiCreationStep.storyBodyByteLimit && bytes < previousBytes) else { return }
            text.wrappedValue = value
        })
    }

    private func inputBox(_ text: Binding<String>, field: Field, label: String, identifier: String) -> some View {
        // Measure the bound text so typing, pasting, and restoring use the same layout.
        // The invisible character gives a trailing line break room for the caret.
        let editorInset = EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)
        return HStack(alignment: .center) {
            Text(verbatim: text.wrappedValue + "\u{200B}")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(editorInset)
                .hidden()
                .accessibilityHidden(true)
                .overlay(alignment: .topLeading) {
                    TextEditor(text: field == .body ? Self.limitedStoryText(text) : Self.limitedText(text))
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .focused(focusedField, equals: field)
                        .accessibilityLabel(label)
                        .accessibilityIdentifier(identifier)
                }
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("입력").foregroundStyle(Color(uiColor: .placeholderText))
                            .padding(editorInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .font(.custom("Paperlogy-3Light", size: 18, relativeTo: .body))
                .tracking(0.36)
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
        VStack(alignment: .leading, spacing: 50) {
            OiCreationSection(title: "이야기 사진", hint: "(1장 이상 3장 이내)") {
                formButton(photoCount == 0 ? "사진 추가하기" : "선택한 사진 보기 · \(photoCount)장",
                           highlighted: false, action: onPhotos)
                    .accessibilityIdentifier("oi.story.editPhotos")
                if photoCount > OiCreationStep.storyPhotoLimit {
                    Text("공개 검토를 요청하려면 사진을 \(OiCreationStep.storyPhotoLimit)장 이하로 줄여 주세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            OiCreationSection(title: "오이 위치 설정") {
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
                .background(highlighted ? Color("OiLight") : Color(white: 244 / 255),
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
