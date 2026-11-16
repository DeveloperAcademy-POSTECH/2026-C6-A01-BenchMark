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
    var storyRepository: any StoryRepository = AppContainer.pilot.storyRepository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedCard: Selection?
    @State private var pendingDetail: Selection?
    @State private var selectedDetail: Selection?

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
            if tab == .collected { sortChoices.padding(.bottom, 7) }
            if let remote, remote.loadError != nil || remote.syncWarning != nil || remote.needsReauthentication {
                OiConnectionStatus(remote: remote, showsInitialProgress: false)
                    .padding(.bottom, 16)
            }
            if tab == .connected {
                ContentUnavailableView("이어진 기부", systemImage: "link",
                    description: Text("연결된 기부 내역은 아직 제공하지 않습니다."))
                    .accessibilityIdentifier("my.v4.connected.unavailable")
            } else if let remote, !remote.hasLoadedRemote {
                if remote.loadError == nil || remote.isRefreshing {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                        .accessibilityLabel("MY 목록을 불러오는 중")
                        .accessibilityIdentifier("my.v4.loading")
                }
            } else if remote?.account == nil {
                signInMessage
            } else if tab == .authored {
                authoredContent
            } else {
                collectedContent
            }
            if tab == .collected && !demo.pinnedOnly {
                MYAppClipCollectionSection(remote: remote, repository: storyRepository)
            }
        }
        .environment(remote)
        .sheet(item: $selectedCard, onDismiss: {
            selectedDetail = pendingDetail
            pendingDetail = nil
        }) { selection in
            cardOverlay(selection)
        }
        .navigationDestination(item: $selectedDetail) { selection in
            if let storyID = selection.ownedStoryID, let remote {
                OiStoryManagement(remote: remote, storyID: storyID)
                    .toolbar(.visible, for: .navigationBar)
            } else if let id = selection.card.storyID, let store = demo.campusStore,
                      let story = store.story(id) {
                CampusCucumberStoryView(story: story, store: store)
            } else {
                MYCardStoryView(card: selection.card)
            }
        }
        .onChange(of: remote?.account?.id) { _, _ in
            selectedCard = nil
            pendingDetail = nil
            selectedDetail = nil
        }
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in
            if let card = selectedCard, card.ownedStoryID == nil,
               let id = card.card.storyID, let story = demo.campusStore?.story(id),
               let authorID = story.authorID, OiContentSafetyStore.shared.isBlocked(authorID) {
                selectedCard = nil
                pendingDetail = nil
            }
        }
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
                ContentUnavailableView {
                    Label("아직 만든 오이가 없어요", systemImage: "leaf")
                } description: {
                    Text("나만의 오이와 이야기를 만들어 보세요.")
                } actions: {
                    if let remote {
                        NavigationLink("오이와 이야기 만들기") { OiStoryListScreen(remote: remote) }
                    }
                }
                .accessibilityIdentifier("my.v4.authored.empty")
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
        if cards.isEmpty {
            if remote?.loadError == nil && remote?.needsReauthentication != true {
                ContentUnavailableView(demo.pinnedOnly ? "고정한 카드가 없어요" : "아직 수집한 카드가 없어요",
                    systemImage: demo.pinnedOnly ? "pin" : "leaf",
                    description: Text(demo.pinnedOnly ? "카드 확대 화면에서 카드를 고정할 수 있어요." : "캠퍼스의 공개 오이 이야기를 수집해 보세요."))
                    .accessibilityIdentifier("my.v4.collected.empty")
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

/// Retains access to this device's App Clip records after the old collection screen is removed.
struct MYAppClipCollectionSection: View {
    let remote: OiRemoteStore?
    @State private var library: CollectedStoryLibrary
    @State private var selected: CollectedStoryLibraryItem?
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    @Environment(\.scenePhase) private var scenePhase

    init(remote: OiRemoteStore?, repository: any StoryRepository, collectionStore: StoryCollectionStore? = nil) {
        self.remote = remote
        _library = State(initialValue: CollectedStoryLibrary(repository: repository,
            collectionStore: collectionStore ?? StoryCollectionStore()))
    }

    var body: some View {
        Group {
            if !library.records.isEmpty || library.persistenceError != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("App Clip에서 수집한 카드").font(.headline)
                    Text("이 기기에 보관된 카드예요. 로그인하면 내 계정에도 저장할 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = library.persistenceError { Text(error).font(.caption).foregroundStyle(.secondary) }
                    if library.isLoading { ProgressView("카드 불러오는 중") }
                    ForEach(library.items) { item in
                        Button { selected = item } label: {
                            Label(item.story.cucumberName, systemImage: "rectangle.portrait")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("my.appClip.card.\(item.id)")
                    }
                    if !library.isLoading && library.items.isEmpty {
                        Text("공개 상태, 차단 설정 또는 연결 상태로 표시할 수 없는 카드가 있어요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("카드 다시 불러오기") { Task { await library.load() } }
                        .disabled(library.isLoading)
                }
                .padding(.vertical, 16)
                .accessibilityIdentifier("my.appClip.collection")
            }
        }
        .task(id: scenePhase) { if scenePhase == .active { await library.load() } }
        .onDisappear { importTask?.cancel() }
        .onChange(of: remote?.account?.id) { _, _ in importTask?.cancel(); selected = nil }
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in
            if let item = selected, OiContentSafetyStore.shared.isBlocked(item.story.donorID) { selected = nil }
        }
        .sheet(item: $selected) { item in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.story.cucumberName).font(.title2.bold())
                        Text(item.story.content)
                        if let id = UUID(uuidString: item.id) {
                            OiStorySafetyButton(storyID: id, authorID: item.story.donorID,
                                authorName: item.story.donorDisplayName, onBlock: { selected = nil })
                        }
                        Button("내 계정에 저장") { importCard(item) }
                            .disabled(importing || remote?.account == nil || remote?.needsReauthentication == true || remote?.isBusy == true)
                            .accessibilityIdentifier("my.appClip.import")
                        if importing { ProgressView() }
                        if let error = remote?.error { Text(error).foregroundStyle(.red) }
                        if let error = library.persistenceError { Text(error).foregroundStyle(.red) }
                        Text("수집일 \(item.record.collectedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(20)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { selected = nil } } }
            }
            .presentationDetents([.large]).presentationDragIndicator(.visible)
            .onDisappear { importTask?.cancel() }
        }
    }

    private func importCard(_ item: CollectedStoryLibraryItem) {
        guard let remote, let owner = remote.account?.id, !remote.needsReauthentication,
              !remote.isBusy, !importing, !OiContentSafetyStore.shared.isBlocked(item.story.donorID) else { return }
        importing = true
        importTask = Task { @MainActor in
            defer { importing = false }
            await remote.perform("collect", payload: ["id": item.id])
            guard !Task.isCancelled, remote.account?.id == owner,
                  remote.collections.contains(where: { $0.storyId.uuidString.caseInsensitiveCompare(item.id) == .orderedSame }) else { return }
            if library.removeImported(storyID: item.id) { selected = nil }
        }
    }
}

private struct MYWorkshopCardArtwork: View {
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
                        OiCucumberPortraitImage(path: path) { path in
                            guard let remote else { throw OiServiceError.unavailable }
                            return try await remote.cucumberImage(path)
                        }
                    } else {
                        Image(card.image).resizable().scaledToFit()
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
