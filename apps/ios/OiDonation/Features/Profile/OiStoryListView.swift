import SwiftUI

struct OiStoryListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let state: OiStoryListState
    var minimumVisibleSlotCount = 4
    var ticketCountText: String?
    var notices: [String] = []
    var onRetry: () -> Void = {}
    var onAddTicket: (() -> Void)?
    var onSelectStory: ((UUID) -> Void)?
    var onCreateStory: (() -> Void)?
    var onUseTicket: (() -> Void)?

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("이야기를 불러오는 중이에요")
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
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("뒤로")
            }

            if let ticketCountText {
                ToolbarItem(placement: .topBarTrailing) {
                    optionalButton(action: onAddTicket) {
                        ticketStatusLabel(ticketCountText)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
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
        ScrollView {
            VStack(spacing: 0) {
                LazyVStack(spacing: 10) {
                    ForEach(state.slots(minimumVisibleCount: minimumVisibleSlotCount)) { slot in
                        if let item = slot.item {
                            storySlot(item)
                        } else {
                            emptySlot(index: slot.index)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)

                if usesAccessibilityLayout {
                    footer
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func ticketStatusLabel(_ countText: String) -> some View {
        HStack(spacing: 10) {
            Text("+")
                .font(.custom("Paperlogy-8ExtraBold", size: 25, relativeTo: .title2))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(ticketColor, in: Circle())

            HStack(spacing: 4) {
                Image("StoryTicketIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)

                Text(countText)
                    .font(.custom("Paperlogy-5Medium", size: 16, relativeTo: .callout))
                    .tracking(0.32)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 15)
        .frame(height: 42)
        .background(ticketBackgroundColor, in: Capsule())
        .overlay {
            Capsule().stroke(ticketColor, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("보유 티켓 \(countText)")
    }

    private func storySlot(_ item: OiStoryListItem) -> some View {
        optionalButton(action: onSelectStory.map { select in { select(item.id) } }) {
            VStack(spacing: 4) {
                Group {
                    if usesAccessibilityLayout {
                        VStack(alignment: .leading, spacing: 12) {
                            storyHeader(item)

                            HStack(alignment: .top, spacing: 12) {
                                storyCucumberImage(item.cucumberAsset)
                                storyMetadata(item)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            storyCucumberImage(item.cucumberAsset)

                            VStack(alignment: .leading, spacing: 12) {
                                storyHeader(item)
                                storyMetadata(item)
                            }
                            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color("OiBorder"), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 2)

                Text(item.dateLabel)
                    .font(.custom("Paperlogy-4Regular", size: 10, relativeTo: .caption2))
                    .tracking(0.2)
                    .foregroundStyle(Color(red: 152 / 255, green: 152 / 255, blue: 152 / 255))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 10, alignment: .trailing)
                    .padding(.horizontal, 20)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storyList.item.\(item.id.uuidString)")
    }

    private func storyCucumberImage(_ asset: String) -> some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 78)
            .frame(width: 86, height: 86)
            .background(Color(red: 239 / 255, green: 239 / 255, blue: 239 / 255), in: RoundedRectangle(cornerRadius: 16))
    }

    private func storyMetadata(_ item: OiStoryListItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("| \(item.donorDisplayName)")
            Text("| \(item.locationDisplayName)")
        }
        .font(.custom("Paperlogy-4Regular", size: 14, relativeTo: .subheadline))
        .tracking(0.28)
        .lineLimit(usesAccessibilityLayout ? 2 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func storyHeader(_ item: OiStoryListItem) -> some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: 8) {
                storyTitle(item.cucumberName)
                tagGroup(item.tags)
            }
        } else {
            HStack(spacing: 4) {
                storyTitle(item.cucumberName)
                Spacer(minLength: 4)
                tagGroup(item.tags)
            }
        }
    }

    private func storyTitle(_ title: String) -> some View {
        Text(title)
            .font(.custom("PearToucan-Regular", size: 20, relativeTo: .title3))
            .tracking(0.8)
            .lineLimit(usesAccessibilityLayout ? 2 : 1)
            .minimumScaleFactor(usesAccessibilityLayout ? 1 : 0.85)
            .layoutPriority(1)
    }

    @ViewBuilder
    private func tagGroup(_ tags: [String]) -> some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: 4) {
                tagLabels(tags)
            }
        } else {
            HStack(spacing: 4) {
                tagLabels(tags)
            }
        }
    }

    @ViewBuilder
    private func tagLabels(_ tags: [String]) -> some View {
        ForEach(Array(tags.prefix(2).enumerated()), id: \.offset) { _, tag in
            Text(tag)
                .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
                .tracking(0.24)
                .foregroundStyle(Color(red: 46 / 255, green: 79 / 255, blue: 22 / 255))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 22)
                .background(Color(red: 197 / 255, green: 224 / 255, blue: 124 / 255), in: Capsule())
        }
    }

    private func emptySlot(index: Int) -> some View {
        VStack(spacing: 4) {
            optionalButton(action: onCreateStory) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        Color(red: 248 / 255, green: 248 / 255, blue: 248 / 255)
                            .shadow(.inner(color: .black.opacity(0.2), radius: 4))
                    )
                    .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112)
                    .overlay {
                        Text("+")
                            .font(.custom("Paperlogy-6SemiBold", size: 40, relativeTo: .title))
                            .foregroundStyle(Color(red: 177 / 255, green: 177 / 255, blue: 177 / 255))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

            Color.clear
                .frame(height: 10)
                .padding(.horizontal, 20)
        }
            .accessibilityLabel("빈 이야기 슬롯")
            .accessibilityIdentifier("storyList.empty.\(index)")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                    Text("* \(notice)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.custom("Paperlogy-4Regular", size: 14, relativeTo: .subheadline))
            .tracking(0.28)
            .foregroundStyle(Color(red: 147 / 255, green: 147 / 255, blue: 147 / 255))
            .lineSpacing(1)

            if usesAccessibilityLayout {
                VStack(spacing: 12) {
                    createStoryFooterButton
                    useTicketFooterButton
                }
            } else {
                HStack(spacing: 20) {
                    createStoryFooterButton
                    useTicketFooterButton
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
                background: Color("OiLight")
            )
        }
    }

    private var useTicketFooterButton: some View {
        optionalButton(action: onUseTicket) {
            footerButtonLabel(
                title: "티켓 사용하기",
                icon: "StoryTicketIcon",
                iconSize: CGSize(width: 30, height: 30),
                foreground: ticketColor,
                background: ticketBackgroundColor
            )
        }
    }

    private func footerButtonLabel(
        title: String,
        icon: String,
        iconSize: CGSize,
        foreground: Color,
        background: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize.width, height: iconSize.height)

            Text(title)
                .font(.custom("Paperlogy-6SemiBold", size: 18, relativeTo: .headline))
                .foregroundStyle(foreground)
                .lineLimit(usesAccessibilityLayout ? 2 : 1)
                .minimumScaleFactor(usesAccessibilityLayout ? 1 : 0.9)
        }
        .padding(.vertical, usesAccessibilityLayout ? 8 : 0)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(background, in: Capsule())
        .shadow(color: foreground.opacity(0.6), radius: 2)
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

    private var ticketColor: Color {
        Color(red: 163 / 255, green: 140 / 255, blue: 33 / 255)
    }

    private var ticketBackgroundColor: Color {
        Color(red: 255 / 255, green: 249 / 255, blue: 223 / 255)
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

extension OiStoryListView {
    static let figmaPreviewNotices = [
        "이야기 저장은 4개까지 가능합니다",
        "출시 전에는 이야기 및 오이를 눌러서 편집할 수 있습니다",
        "티켓을 사용하여 ‘오이&이야기’ 선택 후 출시할 수 있습니다"
    ]
}

#Preview("이야기 2개") {
    NavigationStack {
        OiStoryListView(
            state: .preview,
            ticketCountText: "3pc",
            notices: OiStoryListView.figmaPreviewNotices
        )
    }
}

#Preview("빈 목록") {
    NavigationStack {
        OiStoryListView(
            state: .empty,
            ticketCountText: "3pc",
            notices: OiStoryListView.figmaPreviewNotices
        )
    }
}
