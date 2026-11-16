import SwiftUI

struct OiStoryListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let state: OiStoryListState
    var minimumVisibleSlotCount = OiStoryListState.draftCapacity
    // nil means the seed balance has not been connected; it is not a zero balance.
    var seedCount: Int?
    var onRetry: () -> Void = {}
    var onAddSeed: (() -> Void)?
    var onSelectStory: ((UUID) -> Void)?
    var onCreateStory: (() -> Void)?
    var onUseSeed: (() -> Void)?
    var onDeleteStory: ((UUID) -> Void)?
    var isDeleting = false
    var reviewState: (UUID) -> OiStoryListReviewState = { _ in .unreviewed }
    var onRequestReview: ((UUID) -> Void)?
    var reviewMessage: (UUID) -> String? = { _ in nil }
    var onPlant: (() -> Void)?
    var canPlant = false
    var selectedPlantStoryID: UUID?
    var onCancelPlant: (() -> Void)?

    @State private var showsProductionRules = false

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().accessibilityLabel("이야기를 불러오는 중이에요")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure(let message):
                ContentUnavailableView {
                    Label("이야기를 불러올 수 없어요", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도", action: onRetry)
                }
            case .empty, .content:
                storySlots
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .opacity(isSelectingPlant ? 0 : 1)
                .disabled(isSelectingPlant)
                .accessibilityHidden(isSelectingPlant)
                .accessibilityLabel("닫기")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .topBarTrailing) {
                if let onAddSeed {
                    Button(action: onAddSeed) { OiSeedBalanceLabel(count: seedCount) }
                        .accessibilityIdentifier("storyList.seedBalance")
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsStoryChrome && !usesAccessibilityLayout {
                footer
            }
        }
        .background(screenBackground.ignoresSafeArea())
    }

    private var isSelectingPlant: Bool { onCancelPlant != nil }

    private var screenBackground: Color {
        isSelectingPlant ? Color(oiRGB: 0xe7eecc) : Color(.systemBackground)
    }

    private var showsStoryChrome: Bool {
        switch state {
        case .empty, .content:
            true
        case .loading, .failure:
            false
        }
    }

    private var storySlots: some View {
        let slots = state.slots(minimumVisibleCount: minimumVisibleSlotCount)
        return ScrollViewReader { scroll in
            storyList(slots)
                .onChange(of: isSelectingPlant) { _, _ in
                    if let first = slots.first { scroll.scrollTo(first.id, anchor: .top) }
                }
        }
    }

    private func storyList(_ slots: [OiStoryListSlot]) -> some View {
        List {
            ForEach(slots) { slot in
                Group {
                    if let item = slot.item {
                        VStack(spacing: 0) {
                            storySlot(item)
                            if onRequestReview != nil || isSelectingPlant {
                                reviewRow(item.id, state: reviewState(item.id))
                                    .opacity(isSelectingPlant ? 0 : 1)
                                    .allowsHitTesting(!isSelectingPlant)
                                    .accessibilityHidden(isSelectingPlant)
                            }
                        }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isSelectingPlant, let onDeleteStory {
                                    // Confirm before removing the row; a destructive role here removes it optimistically.
                                    Button {
                                        onDeleteStory(item.id)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                    .tint(.red)
                                    .accessibilityIdentifier("storyList.delete.\(item.id.uuidString)")
                                }
                            }
                    } else {
                        emptySlot(index: slot.index)
                    }
                }
                .disabled(isDeleting)
                // Figma `5400:7649`: 10pt between slots.
                .listRowInsets(EdgeInsets(top: metrics.gap / 2, leading: 20, bottom: metrics.gap / 2, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id(slot.id)
            }
            if usesAccessibilityLayout {
                footer
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.top, Layout.topMargin, for: .scrollContent)
        .contentMargins(.bottom, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("storyList.list")
    }

    /// Figma `5441:17267` (오이가로), shared with the map's region list (`OiCucumberCard`).
    private func storySlot(_ item: OiStoryListItem) -> some View {
        let isSelected = isSelectingPlant && selectedPlantStoryID == item.id
        return optionalButton(action: onSelectStory.map { select in { select(item.id) } }) {
            OiCucumberCard(name: item.cucumberName, tags: item.tags, donor: item.donorDisplayName,
                           title: item.title, metrics: OiCucumberCardMetrics(cardHeight: metrics.cardHeight),
                           selectionOutline: isSelected ? Color(oiRGB: 0x849644) : nil,
                           showsShadow: !isSelectingPlant || !isSelected) {
                if let data = item.portraitPNG, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(item.cucumberAsset).resizable().scaledToFit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("storyList.item.\(item.id.uuidString)")
    }

    // Figma 6101:8975 and 6101:8976.
    private func reviewRow(_ id: UUID, state: OiStoryListReviewState) -> some View {
        let status = Text(state.title)
            .font(.custom("Paperlogy-3Light", size: 13, relativeTo: .caption)).tracking(0.26)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(oiRGB: state.background), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.black)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                status
                Spacer(minLength: 0)
                if state == .unreviewed || state == .rejected {
                    Button {
                        onRequestReview?(id)
                    } label: {
                        Text(OiStoryReviewRequest.title).underline()
                            .foregroundStyle(Color(oiRGB: 0x232323))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("storyList.review.\(id.uuidString)")
                } else {
                    Text("요청 완료").underline().foregroundStyle(Color(oiRGB: 0x737373))
                }
            }
            .accessibilityIdentifier("storyList.reviewStatus.\(id.uuidString)")
            if let message = reviewMessage(id) {
                Text(message).foregroundStyle(.red)
                    .accessibilityIdentifier("storyList.reviewReason.\(id.uuidString)")
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 13, relativeTo: .caption)).tracking(0.26)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func emptySlot(index: Int) -> some View {
        VStack(spacing: 4) {
            optionalButton(action: onCreateStory) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        Color(red: 248 / 255, green: 248 / 255, blue: 248 / 255)
                            .shadow(.inner(color: .black.opacity(0.2), radius: 4))
                    )
                    .frame(maxWidth: .infinity, minHeight: metrics.emptyHeight, maxHeight: metrics.emptyHeight)
                    .overlay {
                        Text("+")
                            .font(.custom("Paperlogy-6SemiBold", size: 40, relativeTo: .title))
                            .foregroundStyle(Color(red: 177 / 255, green: 177 / 255, blue: 177 / 255))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
            }
        }
        .accessibilityLabel("빈 이야기 슬롯")
        .accessibilityIdentifier("storyList.empty.\(index)")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                OiStoryProductionRulesButton(isPresented: $showsProductionRules)
                    .opacity(isSelectingPlant ? 0 : 1)
                    .allowsHitTesting(!isSelectingPlant)
                    .accessibilityHidden(isSelectingPlant)
                if let onCancelPlant {
                    Button(action: onCancelPlant) {
                        Text("취소하기")
                            .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
                            .foregroundStyle(Color(oiRGB: 0x383838))
                            .tracking(0.32)
                            .underline()
                            .frame(minWidth: 108, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                    .accessibilityIdentifier("storyList.cancelPlant")
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)

            if let onPlant {
                Button(action: onPlant) {
                    Text("농장에 오이 심기")
                        .font(.custom("Paperlogy-6SemiBold", size: 18, relativeTo: .headline))
                        .foregroundStyle(seedButtonColor)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background {
                            Capsule().fill(seedButtonBackgroundColor)
                                .shadow(color: seedButtonColor.opacity(0.6), radius: 4)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canPlant || isDeleting)
                .opacity(canPlant && !isDeleting ? 1 : 0.45)
                .accessibilityIdentifier("storyList.plant")
            } else if usesAccessibilityLayout {
                VStack(spacing: 12) {
                    createStoryFooterButton
                    if onUseSeed != nil { useSeedFooterButton }
                }
            } else {
                HStack(spacing: 20) {
                    createStoryFooterButton
                    if onUseSeed != nil { useSeedFooterButton }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, onPlant == nil ? 13 : 2)
        .background(screenBackground)
    }

    private var createStoryFooterButton: some View {
        optionalButton(action: onCreateStory) {
            footerButtonLabel(
                title: "오이 만들기",
                icon: "StoryCreateCucumberIcon",
                iconSize: CGSize(width: 19, height: 30),
                foreground: Color("OiGreen"),
                background: Color("OiLight"),
                glow: Color(red: 125 / 255, green: 151 / 255, blue: 3 / 255)
            )
        }
        // A story awaiting review still uses a slot.
        .disabled(state.isFull)
        .opacity(state.isFull ? 0.4 : 1)
        .accessibilityHint(state.isFull ? "이야기 칸이 모두 찼어요" : "")
        .accessibilityIdentifier("storyList.createStory")
    }

    private var useSeedFooterButton: some View {
        optionalButton(action: onUseSeed) {
            footerButtonLabel(
                title: "씨앗 사용하기",
                icon: "StorySeedIcon",
                iconSize: CGSize(width: 24, height: 26),
                foreground: seedButtonColor,
                background: seedButtonBackgroundColor
            )
        }
        .accessibilityIdentifier("storyList.useSeed")
    }

    private func footerButtonLabel(
        title: String,
        icon: String,
        iconSize: CGSize,
        foreground: Color,
        background: Color,
        glow: Color? = nil
    ) -> some View {
        HStack(spacing: 4) {
            if icon == "StorySeedIcon" {
                OiStorySeedIcon()
            } else {
                Image(icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: iconSize.width, height: iconSize.height)
                    .clipped()
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.custom("Paperlogy-6SemiBold", size: 18, relativeTo: .headline))
                .foregroundStyle(foreground)
                .lineLimit(usesAccessibilityLayout ? 2 : 1)
                .minimumScaleFactor(usesAccessibilityLayout ? 1 : 0.9)
        }
        .padding(.vertical, usesAccessibilityLayout ? 8 : 0)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background {
            Capsule().fill(background)
                .shadow(color: (glow ?? foreground).opacity(0.6), radius: 2)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func optionalButton<Label: View>(
        action: (() -> Void)?,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if let action {
            Button(action: action, label: label)
                .buttonStyle(.plain)
        } else {
            label()
        }
    }

    private var seedButtonColor: Color {
        Color(red: 163 / 255, green: 140 / 255, blue: 33 / 255)
    }

    private var seedButtonBackgroundColor: Color {
        Color(red: 255 / 255, green: 249 / 255, blue: 223 / 255)
    }

    private enum Layout {
        static let topMargin: CGFloat = 15
    }

    private struct SlotMetrics {
        let gap: CGFloat = 10
        let cardHeight: CGFloat = 110
        let emptyHeight: CGFloat = 112
        let cardPadding: CGFloat = 12
        let textSpacing: CGFloat = 20
        let imageHeight: CGFloat = 86
    }

    private let metrics = SlotMetrics()

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

// Figma 6101:9175 and 6101:9195. SwiftUI provides the system material and arrow.
struct OiStoryProductionRulesButton: View {
    @Binding var isPresented: Bool
    @ScaledMetric(relativeTo: .caption) private var ruleLineHeight: CGFloat = 24

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text("오이 제작 규정")
                    .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
                    .tracking(0.32)
                    .underline()
            }
            .foregroundStyle(Color(oiRGB: 0x737373))
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("storyList.productionRules")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                rule(Text("이야기 저장은 \(Text("\(OiStoryListState.draftCapacity)개").foregroundStyle(.red))까지 가능합니다"))
                rule(Text("농장에 심기 전에는 저장된 오이를 눌러서 편집할 수 있습니다"))
                rule(Text("저장된 오이를 슬라이드하여 삭제할 수 있습니다"))
                rule(Text("내용 검토가 완료되어야 농장에 오이를 심을 수 있습니다"))
            }
            .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
            .tracking(0.24)
            .foregroundStyle(Color(oiRGB: 0x232323))
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .frame(idealWidth: 362, maxWidth: 362, alignment: .leading)
            .accessibilityIdentifier("storyList.productionRulesContents")
            .presentationCompactAdaptation(.popover)
            .presentationCornerRadius(38)
            .presentationBackground(.regularMaterial)
        }
    }

    private func rule(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("*").accessibilityHidden(true)
            text.fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: ruleLineHeight, alignment: .leading)
    }
}

struct OiSeedBalanceLabel: View {
    let count: Int?

    var body: some View {
        HStack(spacing: 10) {
            Text("+")
                .font(.custom("Paperlogy-7Bold", size: 25, relativeTo: .title2))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(seedBalanceBorderColor, in: Circle())

            HStack(spacing: 4) {
                OiStorySeedIcon()
                Text(count.map { "\($0)pc" } ?? "—pc")
                    .font(.custom("Paperlogy-5Medium", size: 16, relativeTo: .callout))
                    .tracking(0.32)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 15)
        .frame(minHeight: 44)
        .background(seedBalanceBackgroundColor, in: Capsule())
        .overlay { Capsule().stroke(seedBalanceBorderColor, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("씨앗 추가")
        .accessibilityValue(count.map { "\($0)개" } ?? "개수 확인 준비 중")
        .accessibilityHint("씨앗 안내 열기")
    }

    private var seedBalanceBorderColor: Color {
        Color(red: 198 / 255, green: 191 / 255, blue: 91 / 255)
    }

    private var seedBalanceBackgroundColor: Color {
        Color(red: 255 / 255, green: 254 / 255, blue: 228 / 255)
    }
}

struct OiStorySeedIcon: View {
    /// The Figma image fill crops the square source into a 24 × 26 point slot.
    var body: some View {
        Color.clear.frame(width: 24, height: 26)
            .overlay(alignment: .topLeading) {
                Image("StorySeedIcon").resizable()
                    .frame(width: 24 * 1.5794, height: 26 * 1.4569)
                    .offset(x: -24 * 0.2991, y: -26 * 0.2155)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

#Preview("이야기 2개") {
    NavigationStack {
        OiStoryListView(
            state: .preview,
            seedCount: 3,
            onAddSeed: {}, onCreateStory: {}, onUseSeed: {}
        )
    }
}

#Preview("빈 목록") {
    NavigationStack {
        OiStoryListView(
            state: .empty,
            seedCount: 0,
            onAddSeed: {}, onCreateStory: {}, onUseSeed: {}
        )
    }
}

private var storyPlantSelectionPreview: some View {
    NavigationStack {
        OiStoryListView(state: .preview, minimumVisibleSlotCount: 0, onSelectStory: { _ in },
            reviewState: { _ in .approved }, onPlant: {}, canPlant: true,
            selectedPlantStoryID: OiStoryListState.preview.items.first?.id, onCancelPlant: {})
    }
}

#Preview("심을 오이 선택 · 기준", traits: .fixedLayout(width: 402, height: 874)) {
    storyPlantSelectionPreview
}

#Preview("심을 오이 선택 · 작은 화면", traits: .fixedLayout(width: 375, height: 667)) {
    storyPlantSelectionPreview
}

#Preview("심을 오이 선택 · 큰 화면", traits: .fixedLayout(width: 440, height: 956)) {
    storyPlantSelectionPreview
}
