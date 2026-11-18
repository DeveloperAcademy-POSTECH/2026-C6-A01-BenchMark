//
//  MYWorkshopContent.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/16/26.
//

import SwiftUI

enum MYWorkshopTab: String, CaseIterable, Identifiable {
    case authored = "나의 기부"
    case connected = "이어진 기부"
    case collected = "수집한 기부"

    var id: Self { self }
}

/// Reuses account stories and collected cards without treating them as verified donations.
struct MYWorkshopContent: View {
    let tab: MYWorkshopTab
    let demo: MYLibraryStore
    var remote: OiRemoteStore?
    var emptyTopPadding: CGFloat = 175
    var onExploreMap: () -> Void = {}
    var storyRepository: any StoryRepository = AppContainer.pilot.storyRepository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedCard: Selection?
    @State private var pendingDetail: Selection?
    @State private var selectedDetail: Selection?
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false

    private struct Selection: Identifiable, Hashable {
        let card: MYCard
        var ownedStoryID: UUID?
        var id: String { card.id }
    }

    private var authoredStories: [OiLiveStory] {
        guard let remote, let owner = remote.account?.id else { return [] }
        return remote.ownStories.filter { $0.userId == owner && $0.status != "deleted" }
    }

    private var cards: [MYCard] {
        demo.collectionCards(school: nil, sort: demo.collectionSort, pinnedOnly: demo.pinnedOnly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tab == .collected, remote?.account != nil, !demo.cards.isEmpty { sortChoices.padding(.bottom, 7) }
            if let remote, remote.loadError != nil || remote.syncWarning != nil || remote.needsReauthentication {
                OiConnectionStatus(remote: remote, showsInitialProgress: false)
                    .padding(.bottom, 16)
            }
            if remote?.account == nil || remote?.needsReauthentication == true {
                signInMessage
            } else if tab == .connected {
                OiContinuationList(emptyContent: {
                    AnyView(emptyState(for: .connected) {
                        Button(action: onExploreMap) { emptyActionLabel("다른 오이 구경하기 →") }
                    })
                })
            } else if let remote, !remote.hasLoadedRemote {
                if remote.loadError == nil || remote.isRefreshing {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                        .accessibilityLabel("MY 목록을 불러오는 중")
                        .accessibilityIdentifier("my.v4.loading")
                }
            } else if tab == .authored {
                authoredContent
            } else {
                collectedContent
            }
        }
        .environment(remote)
        .sheet(item: $selectedCard, onDismiss: {
            importTask?.cancel()
            selectedDetail = pendingDetail
            pendingDetail = nil
        }) { selection in
            cardOverlay(selection)
        }
        .navigationDestination(item: $selectedDetail) { selection in
            if let storyID = selection.ownedStoryID, let remote {
                OiAuthoredStoryDestination(remote: remote, storyID: storyID)
            } else if let id = selection.card.storyID, let store = demo.campusStore,
                      let story = store.story(id) {
                CampusCucumberStoryView(story: story, store: store)
            } else if selection.card.storyID == nil {
                MYCardStoryView(card: selection.card)
            }
        }
        .onChange(of: remote?.account?.id) { _, _ in
            importTask?.cancel()
            selectedCard = nil
            pendingDetail = nil
            selectedDetail = nil
        }
        .onDisappear { importTask?.cancel() }
        .onChange(of: demo.cards.map(\.id)) { _, _ in closeUnavailableCards() }
        .onChange(of: remote?.revision) { _, _ in closeUnavailableCards() }
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in closeUnavailableCards() }
    }

    private func closeUnavailableCards() {
        guard let remote else { return }
        let publishedIDs = Set(remote.stories.map(\.id))
        let collectedIDs = Set(demo.cards.map(\.id))
        func unavailable(_ selection: Selection?) -> Bool {
            guard let selection, selection.ownedStoryID == nil,
                  let id = selection.card.storyID.flatMap(UUID.init(uuidString:)) else { return false }
            return !publishedIDs.contains(id) || !collectedIDs.contains(selection.id)
        }
        if unavailable(selectedCard) { selectedCard = nil }
        if unavailable(pendingDetail) { pendingDetail = nil }
        if unavailable(selectedDetail) { selectedDetail = nil }
    }

    private var signInMessage: some View {
        ContentUnavailableView {
            Label("로그인 후 사용할 수 있어요", systemImage: "person.crop.circle")
        } description: {
            Text("내가 만든 이야기와 수집한 카드를 확인해 보세요.")
        } actions: {
            NavigationLink("로그인하기") { MYSettingsView(demo: demo, remote: remote) }
                .accessibilityIdentifier("my.v4.signIn")
        }
    }

    @ViewBuilder private var authoredContent: some View {
        if authoredStories.isEmpty {
            if remote?.loadError == nil && remote?.needsReauthentication != true {
                emptyState(for: .authored) {
                    if let remote {
                        NavigationLink { OiStoryListScreen(remote: remote) } label: {
                            emptyActionLabel("오이 만들기 →")
                        }
                    }
                }
            }
        } else if let remote {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(authoredStories) { story in
                    let card = authoredCard(story, remote: remote)
                    cardButton(.init(card: card, ownedStoryID: story.id),
                               label: "\(story.cucumberName), \(story.status.oiStatusTitle), 내 이야기 카드 확대")
                        .accessibilityIdentifier("my.v4.story.\(story.id.uuidString)")
                }
            }
        }
    }

    @ViewBuilder private var collectedContent: some View {
        if let error = demo.clipCollection.persistenceError {
            Text(error).font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
        }
        if cards.isEmpty {
            if remote?.loadError == nil && remote?.needsReauthentication != true {
                if demo.pinnedOnly, !demo.cards.isEmpty {
                    ContentUnavailableView("고정한 카드가 없어요", systemImage: "pin",
                        description: Text("카드 확대 화면에서 카드를 고정할 수 있어요."))
                } else if demo.clipCollection.persistenceError == nil {
                    emptyState(for: .collected) {
                        Button(action: onExploreMap) { emptyActionLabel("수집하러 가기 →") }
                    }
                }
            }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(cards) { card in
                    cardButton(.init(card: card), label: "\(card.title) 수집 카드 확대")
                        .accessibilityIdentifier("my.v4.card.\(card.id)")
                }
            }
        }
    }

    private func emptyState<Action: View>(for tab: MYWorkshopTab, @ViewBuilder action: () -> Action) -> some View {
        let message: String = switch tab {
        case .authored: "기부한 오이가 없습니다"
        case .connected: "이어진 기부가 없습니다"
        case .collected: "수집한 기부가 없습니다"
        }
        return VStack(spacing: 27) {
            Text(message)
                .font(CampusStyle.medium(22)).tracking(0.44)
                .foregroundStyle(Color("OiGreen"))
                .multilineTextAlignment(.center)
                .frame(width: dynamicTypeSize <= .large ? 209 : nil,
                       height: dynamicTypeSize <= .large ? 20 : nil)
                .accessibilityAddTraits(.isHeader)
            action().buttonStyle(.plain)
                .padding(.trailing, tab == .connected ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.trailing, 1)
        .padding(.top, max(0, emptyTopPadding - (tab == .collected ? 1 : 0)))
        .accessibilityIdentifier("my.v4.\(tab == .authored ? "authored" : tab == .connected ? "connected" : "collected").empty")
    }

    private func emptyActionLabel(_ title: String) -> some View {
        let textWidth: CGFloat = switch tab {
        case .authored: 113
        case .connected: 172
        case .collected: 131
        }
        return Text(title)
            .font(CampusStyle.body(20)).tracking(0.4)
            .foregroundStyle(.black).multilineTextAlignment(.center)
            .frame(width: dynamicTypeSize <= .large ? textWidth : nil,
                   height: dynamicTypeSize <= .large ? 20 : nil)
            .padding(.horizontal, 30).padding(.vertical, 15)
            .frame(minHeight: 50)
            .background(.white, in: Capsule())
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.adaptive(minimum: 150), spacing: 8.5)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 8.5), count: 3)
    }

    private var sortChoices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { sortButtons }
            VStack(alignment: .leading, spacing: 0) { sortButtons }
        }
    }

    @ViewBuilder private var sortButtons: some View {
        ForEach(MYCardSort.allCases, id: \.self) { option in
            Button { demo.collectionSort = option } label: {
                Text(option.rawValue)
                    .font(.custom(demo.collectionSort == option ? "Paperlogy-5Medium" : "Paperlogy-4Regular", size: 16, relativeTo: .body))
                    .tracking(0.32)
                    .foregroundStyle(demo.collectionSort == option ? Color(red: 247 / 255, green: 1, blue: 233 / 255) : .black)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(demo.collectionSort == option ? Color(red: 153 / 255, green: 185 / 255, blue: 99 / 255) : .white, in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(demo.collectionSort == option ? .isSelected : [])
            .accessibilityIdentifier("my.sort.\(option)")
        }
        Button { demo.pinnedOnly.toggle() } label: {
            Image(systemName: "pin.fill").font(.system(size: 14, weight: .bold))
                .foregroundStyle(demo.pinnedOnly ? .white : .black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(demo.pinnedOnly ? Color(red: 153 / 255, green: 185 / 255, blue: 99 / 255) : .white, in: Capsule())
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("고정한 카드만 보기")
        .accessibilityAddTraits(demo.pinnedOnly ? .isSelected : [])
        .accessibilityIdentifier("my.pinned")
    }

    private func cardButton(_ selection: Selection, label: String) -> some View {
        Button { selectedCard = selection } label: {
            MYWorkshopCardArtwork(card: selection.card, remote: remote)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func authoredCard(_ story: OiLiveStory, remote: OiRemoteStore) -> MYCard {
        let region = remote.regions.first { $0.id == story.regionId }
        let school = remote.schools.first { $0.id == region?.schoolId }
        return MYCard(id: story.id.uuidString, title: story.cucumberName, image: story.cucumberAsset,
            school: MYSchool(id: school?.id ?? "", name: school?.name ?? "학교 정보 확인 중"), order: 0,
            body: story.body, donor: remote.profile?.publicName ?? remote.profile?.farmName ?? "오이",
            date: story.createdDateLabel, storyID: story.id.uuidString, appearance: story.cardAsset,
            cucumberPortraitPath: story.cucumberArtwork?.path(.portrait), cardArtworkPath: story.cardArtworkPath)
    }

    private func cardOverlay(_ selection: Selection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MYCardArtwork(card: selection.card).frame(maxWidth: 362)
                        .accessibilityLabel("\(selection.card.title) 카드")
                    HStack(spacing: 7) {
                        Button {
                            pendingDetail = selection
                            selectedCard = nil
                        } label: {
                            Text("자세히 보기").font(CampusStyle.medium(20))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(.white, in: Capsule())
                        }
                        .accessibilityIdentifier("my.card.details")
                        if selection.ownedStoryID == nil {
                            Button { demo.toggleFavorite(selection.card) } label: {
                                Image(systemName: "pin.fill").font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(demo.favorites.contains(selection.id) ? CampusStyle.green : .black)
                                    .frame(width: 49, height: 44).background(.white, in: Capsule())
                            }
                            .disabled(remote?.isBusy == true || remote?.needsReauthentication == true)
                            .accessibilityLabel("카드 고정 \(demo.favorites.contains(selection.id) ? "해제" : "추가")")
                            .accessibilityAddTraits(demo.favorites.contains(selection.id) ? .isSelected : [])
                            .accessibilityIdentifier("my.favorite.\(selection.id)")
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(.black).frame(maxWidth: 362)
                    if selection.ownedStoryID == nil, demo.clipRecord(for: selection.card) != nil {
                        Button("내 계정에 저장") {
                            guard let remote, !importing else { return }
                            importing = true
                            importTask = Task { @MainActor in
                                defer { importing = false }
                                _ = await demo.importClipCard(selection.card, into: remote)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(importing || remote?.isBusy == true || remote?.needsReauthentication == true)
                        .accessibilityIdentifier("my.appClip.import")
                        Text("이 기기에서 수집한 카드예요. 내 계정에 저장하면 다른 기기에서도 볼 수 있어요.")
                            .font(.caption).foregroundStyle(.white)
                        if importing { ProgressView().tint(.white) }
                        if let error = demo.clipCollection.persistenceError {
                            Text(error).font(.caption).foregroundStyle(.white)
                        }
                    }
                    if let remote, let error = remote.error {
                        Text(error).font(.footnote).foregroundStyle(.white)
                    }
                }.padding(20).frame(maxWidth: .infinity)
            }
            .background(Color.black.opacity(0.88).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기", systemImage: "xmark") { selectedCard = nil }
                        .labelStyle(.iconOnly).accessibilityIdentifier("my.card.close")
                }
            }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct MYWorkshopCardArtwork: View {
    let card: MYCard
    let remote: OiRemoteStore?

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 115
            ZStack(alignment: .topLeading) {
                MYCardArtwork(card: card).frame(width: geometry.size.width, height: 159 * scale)
                Image("MYProfileCardShadow").resizable()
                    .frame(width: 122 * scale, height: 159 * scale)
                    .offset(x: -31 * scale, y: 50 * scale)
                    .allowsHitTesting(false)
                Group {
                    if let path = card.cucumberPortraitPath {
                        OiCucumberPortraitImage(path: path, requiresTransparentBackground: true) { path in
                            guard let remote else { throw OiServiceError.unavailable }
                            return try await remote.cucumberImage(path)
                        }
                    } else {
                        OiCucumberPortraitImage(path: "asset/\(card.image)", requiresTransparentBackground: true) { _ in
                            guard let image = UIImage(named: card.image) else { throw OiCharacterPortraitCutout.Failure.unreadable }
                            return image
                        }
                    }
                }
                .frame(width: 43 * scale, height: 85 * scale)
                .offset(x: 8 * scale, y: 87 * scale)
            }
        }
        .aspectRatio(115.0 / 172.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
