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
    var onShowReviewFailure: ((UUID) -> Void)?
    var onPlant: (() -> Void)?
    var canPlant = false

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
        .background(Color(.systemBackground).ignoresSafeArea())
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
        List {
            ForEach(state.slots(minimumVisibleCount: minimumVisibleSlotCount)) { slot in
                Group {
                    if let item = slot.item {
                        VStack(spacing: 0) {
                            storySlot(item)
                            if onRequestReview != nil { reviewRow(item.id, state: reviewState(item.id)) }
                        }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if let onDeleteStory {
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

    /// Figma `5441:17267` (오이가로): name, tags and donor, then the title, with the cucumber on the right.
    private func storySlot(_ item: OiStoryListItem) -> some View {
        optionalButton(action: onSelectStory.map { select in { select(item.id) } }) {
                Group {
                    if usesAccessibilityLayout {
                        VStack(alignment: .leading, spacing: 12) {
                            storyText(item)
                            storyCucumberImage(item)
                        }
                    } else {
                        HStack(spacing: 10) {
                            storyText(item)
                            storyCucumberImage(item)
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .padding(.vertical, metrics.cardPadding)
                .frame(maxWidth: .infinity, minHeight: metrics.cardHeight,
                       maxHeight: usesAccessibilityLayout ? nil : metrics.cardHeight, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28).strokeBorder(Color(oiRGB: 0xebebeb), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storyList.item.\(item.id.uuidString)")
    }

    // Figma 6101:8975 and 6101:8976.
    private func reviewRow(_ id: UUID, state: OiStoryListReviewState) -> some View {
        let status = Text(state.title)
            .font(.custom("Paperlogy-3Light", size: 13, relativeTo: .caption)).tracking(0.26)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(oiRGB: state.background), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.black)
        return HStack(spacing: 8) {
            if state == .rejected, let onShowReviewFailure {
                Button { onShowReviewFailure(id) } label: { status }
                    .buttonStyle(.plain)
                    .accessibilityHint("거부 사유 보기")
            } else {
                status
            }
            Spacer(minLength: 0)
            if state == .unreviewed || state == .rejected {
                Button {
                    onRequestReview?(id)
                } label: {
                    Text("내용 검토 요청하기").underline()
                        .foregroundStyle(Color(oiRGB: 0x232323))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("storyList.review.\(id.uuidString)")
            } else {
                Text("요청 완료").underline().foregroundStyle(Color(oiRGB: 0x737373))
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 13, relativeTo: .caption)).tracking(0.26)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func storyText(_ item: OiStoryListItem) -> some View {
        VStack(alignment: .leading, spacing: metrics.textSpacing * 0.6) {
            VStack(alignment: .leading, spacing: metrics.textSpacing * 0.4) {
                Text(item.cucumberName)
                    .font(.custom("YANGJIN", size: 22, relativeTo: .title2))
                    .tracking(0.44)
                    .foregroundStyle(.black)
                    .lineLimit(usesAccessibilityLayout ? nil : 1)
                    .minimumScaleFactor(usesAccessibilityLayout ? 1 : 0.8)
                    .frame(minHeight: 20, alignment: .bottomLeading)

                storyTagsAndDonor(item)
            }
            if !item.title.isEmpty {
                Text(item.title)
                    .font(.custom("Paperlogy-3Light", size: 18, relativeTo: .body))
                    .foregroundStyle(.black)
                    .lineLimit(usesAccessibilityLayout ? nil : 1)
                    .frame(minHeight: 18, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func storyTagsAndDonor(_ item: OiStoryListItem) -> some View {
        let tags = HStack(spacing: 4) {
            ForEach(Array(item.tags.prefix(2).enumerated()), id: \.offset) { _, tag in
                Text("#" + tag).foregroundStyle(Self.tagColor)
            }
        }
        let donor = Text(item.donorDisplayName).foregroundStyle(Self.donorColor)
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 4) { tags; donor }
            } else {
                HStack(spacing: 6) { tags; donor }
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
        .tracking(0.24)
        .lineLimit(usesAccessibilityLayout ? nil : 1)
    }

    private func storyCucumberImage(_ item: OiStoryListItem) -> some View {
        Group {
            if let data = item.portraitPNG, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(item.cucumberAsset).resizable().scaledToFit()
            }
        }
        .frame(width: 50 * metrics.imageHeight / 86, height: 78 * metrics.imageHeight / 86)
        .frame(width: 66 * metrics.imageHeight / 86, height: metrics.imageHeight)
        .background(Color(red: 239 / 255, green: 239 / 255, blue: 239 / 255), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }

    private static let tagColor = Color(red: 79 / 255, green: 110 / 255, blue: 223 / 255)
    private static let donorColor = Color(red: 83 / 255, green: 83 / 255, blue: 83 / 255)

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
            OiStoryProductionRulesButton(isPresented: $showsProductionRules)
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
        .padding(.bottom, 13)
        .background(Color(.systemBackground))
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
        // All draft slots are taken; finish or delete one to start another (#368).
        .disabled(state.isFull)
        .opacity(state.isFull ? 0.4 : 1)
        .accessibilityHint(state.isFull ? "임시저장 칸이 모두 찼어요. 오이를 삭제하거나 제출하면 새로 만들 수 있어요" : "")
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
