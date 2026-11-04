import SwiftUI

struct OiCreationProgressHeader: View {
    let step: Int
    var onPrevious: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(step) / 4 · \(title(step))").font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let onPrevious {
                        Button("이전 단계로 이동", action: onPrevious).font(.body)
                            .frame(minHeight: 44)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                footprints
            }
        }
        .foregroundStyle(Color("OiDark"))
        .frame(minHeight: 64)
    }

    private var footprints: some View {
        HStack(spacing: 5) {
            ForEach(1...4, id: \.self) { number in
                if number == step - 1, let onPrevious {
                    Button(action: onPrevious) { footprint(number) }.buttonStyle(.plain)
                        .accessibilityLabel("이전 단계로 이동")
                } else {
                    footprint(number)
                        .accessibilityLabel("\(number)단계, \(title(number))\(number == step ? ", 현재 단계" : "")")
                }
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    private func footprint(_ number: Int) -> some View {
        let lowered = number.isMultiple(of: 2)
        let reached = number <= step
        return VStack(spacing: 0) {
            if lowered { stepLabel(number).frame(minHeight: 29, alignment: .bottom) }
            ZStack {
                if lowered {
                    Image("ConsentStepInactiveLowered").resizable().renderingMode(.template)
                        .foregroundStyle(reached ? Color("OiGreen") : Color("OiBorder"))
                        .frame(width: 69.8566, height: 29.991)
                } else {
                    Image(reached ? "ConsentStepActive" : "ConsentStepInactiveRaised")
                        .resizable().frame(width: 65.6168, height: 38.4729)
                        .rotationEffect(.degrees(16.63))
                }
                Text("STEP \(number)").font(.custom("Paperlogy-7Bold", size: 10, relativeTo: .caption2))
                    .foregroundStyle(reached ? Color("OiSoft").opacity(number == step ? 1 : 0.4) : Color("OiGreen").opacity(0.5))
            }.frame(height: lowered ? 35 : 39)
            if !lowered { stepLabel(number).frame(minHeight: 25, alignment: .top) }
        }.frame(maxWidth: .infinity, minHeight: 64)
            .accessibilityElement(children: .ignore)
    }
    private func stepLabel(_ number: Int) -> some View {
        Text(number == step - 1 ? "이전으로" : title(number))
            .opacity(number == step ? 1 : number < step ? 0.3 : 0)
            .minimumScaleFactor(0.8)
    }
    private func title(_ number: Int) -> String {
        ["약관동의", "이야기작성", "오이커스텀", "카드커스텀"][number - 1]
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
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("완료").font(CampusStyle.medium(20)).tracking(0.4)
                .padding(.horizontal, 20).frame(minHeight: 44)
                .background(Color("OiBorder"), in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(.primary).disabled(!enabled)
    }
}

struct OiCreationSection<Content: View>: View {
    let title: String
    var hint: String = ""
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let headingLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            headingLayout {
                Text(title).font(.custom("Paperlogy-6SemiBold", size: 26, relativeTo: .title2))
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
    @Binding var draft: OiStoryDraft
    let grants: [OiWritingGrant]
    static let themes = ["가족", "우정", "사랑", "성장", "도전", "꿈", "배움", "경쟁", "협력", "갈등", "화해", "일탈", "나눔", "응원", "성취", "기타"]
    static let emotions = ["행복함", "즐거움", "뿌듯함", "고마움", "편안함", "설렘", "따뜻함", "짜릿함", "놀라움", "신남", "벅참", "그리움", "후련함", "부끄러움", "후회", "긴장감", "슬픔", "화남", "아쉬움", "기타"]
    var body: some View {
        VStack(alignment: .leading, spacing: 50) {
            OiCreationSection(title: "테마 선택", hint: "(택 1)") { tags(Self.themes, selected: $draft.theme) }
            OiCreationSection(title: "감정 선택", hint: "(택 1)") { tags(Self.emotions, selected: $draft.emotion) }
            OiCreationSection(title: "제목 입력", hint: "\(draft.title.count) / 100") {
                HStack(alignment: .firstTextBaseline) {
                    TextField("이야기 제목", text: $draft.title, axis: .vertical)
                        .accessibilityIdentifier("oi.draft.title")
                    Image(systemName: "pencil").accessibilityHidden(true)
                }.padding(20).background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 20))
            }
            OiCreationSection(title: "내용 입력", hint: "\(draft.body.count) / 10,000") {
                TextField("오래 남기고 싶은 이야기를 들려주세요", text: $draft.body, axis: .vertical)
                    .lineLimit(7...16).accessibilityIdentifier("oi.draft.body").padding(20)
                    .background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 20))
            }
            if grants.count > 1 {
                Picker("사용할 작성 승인", selection: $draft.grantId) {
                    Text("승인 선택").tag(Optional<UUID>.none)
                    ForEach(grants) { Text("승인 \($0.id.uuidString.prefix(8)) · 최대 \($0.storyLimit)개").tag(Optional($0.id)) }
                }.disabled(draft.revision > 0)
            }
        }.font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
    }
    private func tags(_ values: [String], selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OiCreationTagLayout {
                ForEach(values, id: \.self) { value in
                    Button { selected.wrappedValue = value } label: {
                        Text(value).tracking(0.32).padding(.horizontal, 20).frame(minHeight: 34)
                            .foregroundStyle(selected.wrappedValue == value ? Color.white : Color("OiDark"))
                            .background(selected.wrappedValue == value ? Color("OiGreen") : CampusStyle.mapSheet, in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.wrappedValue == value ? .isSelected : [])
                }
            }
            if !selected.wrappedValue.isEmpty && !values.contains(selected.wrappedValue) {
                Text("기존 선택: \(selected.wrappedValue)").font(.caption).foregroundStyle(.secondary)
            }
        }
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
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + 10; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
