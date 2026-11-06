//
//  MYCollectionView.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import SwiftUI

struct MYCollectionView: View {
    let demo: MYLibraryStore
    let school: MYSchool?
    var remote: OiRemoteStore?
    @State private var collectedLibrary: CollectedStoryLibrary
    private var sort: MYCardSort {
        get { demo.collectionSort }
        nonmutating set { demo.collectionSort = newValue }
    }
    private var pinnedOnly: Bool {
        get { demo.pinnedOnly }
        nonmutating set { demo.pinnedOnly = newValue }
    }
    @State private var selectedCard: MYCard?
    @State private var selectedCollectedCard: CollectedStoryLibraryItem?
    @State private var detailCard: MYCard?
    @State private var selectedDetail: MYCard?
    @ScaledMetric(relativeTo: .body) private var emptyCollectionLineHeight = 27.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dismiss) private var dismiss

    private var filter: MYCollectionFilter { demo.collectionFilter }
    private var cards: [MYCard] { demo.collectionCards(school: school, sort: sort, pinnedOnly: pinnedOnly) }
    private var showsFolders: Bool { filter == .schools && school == nil }
    private var collectionBackground: Color {
        school == nil ? Color(.systemBackground) : Color(red: 186 / 255, green: 154 / 255, blue: 95 / 255)
    }
    private var schools: [MYSchool] {
        Array(Set(cards.map(\.school))).sorted { $0.name < $1.name }
    }

    init(
        demo: MYLibraryStore,
        school: MYSchool? = nil,
        storyRepository: any StoryRepository,
        remote: OiRemoteStore? = nil,
        collectionStore: StoryCollectionStore? = nil
    ) {
        self.demo = demo
        self.remote = remote
        self.school = school
        _collectedLibrary = State(
            initialValue: CollectedStoryLibrary(
                repository: storyRepository,
                collectionStore: collectionStore ?? StoryCollectionStore()
            )
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize { sortBar }
            if let remote { OiConnectionStatus(remote: remote, showsInitialProgress: false) }
            if let error = collectedLibrary.persistenceError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("my.appClip.storageError")
            }
            GeometryReader { geometry in
                ScrollView {
                    if dynamicTypeSize.isAccessibilitySize { sortBar.padding(.bottom, 12) }
                    if shouldShowCollectedSection {
                        collectedSection
                    }
                    if let remote, !remote.hasLoadedRemote {
                        if !isLoadingCollectedSection && (remote.loadError == nil || remote.isRefreshing) {
                            ProgressView().accessibilityLabel("도감을 불러오는 중")
                        }
                    } else if showsFolders && !schools.isEmpty {
                        schoolFolders
                    } else if !cards.isEmpty {
                        cardGrid
                    } else if !shouldShowCollectedSection && collectedLibrary.persistenceError == nil && canShowEmptyCollection {
                        if canShowIllustratedEmptyCollection {
                            illustratedEmptyCollection
                                .frame(minHeight: max(0, geometry.size.height - 20))
                                .padding(.top, 4)
                        } else {
                            ContentUnavailableView(pinnedOnly ? "즐겨찾는 오이가 없어요" : "아직 수집한 카드가 없어요", systemImage: pinnedOnly ? "pin" : "leaf", description: Text(emptyCollectionGuidance))
                                .padding(.top, 60)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .clipped()
        }
        .padding(.horizontal, 20)
        .background(collectionBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            OiSettingsHeader(title: school?.rawValue ?? "도감", back: { dismiss() }, backgroundColor: collectionBackground,
                             titleColor: school == nil ? Color(red: 117 / 255, green: 75 / 255, blue: 0)
                                 : Color(red: 105 / 255, green: 79 / 255, blue: 33 / 255))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if school == nil {
                collectionFilters
                    .background(dynamicTypeSize.isAccessibilitySize ? Color(.systemBackground) : .clear)
            }
        }
        .task { await collectedLibrary.load() }
        .refreshable { await collectedLibrary.load() }
        .sheet(item: $selectedCard, onDismiss: {
            if let card = detailCard { detailCard = nil; selectedDetail = card }
        }) { card in
            cardOverlay(card)
        }
        .sheet(item: $selectedCollectedCard) { item in
            collectedCardOverlay(item)
        }
        .navigationDestination(item: $selectedDetail) { card in
            if let id = card.storyID, let store = demo.campusStore, let story = store.story(id) {
                CampusStoryDetailView(story: story, store: store)
            } else { MYCardStoryView(card: card) }
        }
    }

    private var emptyCollectionGuidance: String {
        if pinnedOnly { return "카드 확대 화면의 핀을 눌러 이 화면에 모아보세요." }
        if remote?.account == nil { return "로그인 후 캠퍼스의 공개 오이 이야기를 수집해 보세요." }
        return "캠퍼스의 공개 오이 이야기를 수집해 보세요."
    }

    private var canShowEmptyCollection: Bool {
        guard let remote else { return true }
        return remote.account != nil && remote.loadError == nil && !remote.needsReauthentication
    }

    private var canShowIllustratedEmptyCollection: Bool {
        canShowEmptyCollection && !pinnedOnly
    }

    private var illustratedEmptyCollection: some View {
        VStack(spacing: 16) {
            Image("MYEmptyCollection")
                .resizable()
                .scaledToFit()
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 96 : 192,
                       height: dynamicTypeSize.isAccessibilitySize ? 150 : 300)
                .accessibilityHidden(true)

            Text("아직 수집한 오이카드가 없습니다\n동문들의 카드를 수집하고\n나만의 도감을 만들어보세요!")
                .font(CampusStyle.medium(18))
                .tracking(0.36)
                .lineHeight(.exact(points: emptyCollectionLineHeight))
                .foregroundStyle(school != nil ? Color.black : (colorScheme == .dark || colorSchemeContrast == .increased
                    ? Color.primary : Color("OiGreen")))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("my.collection.illustratedEmpty")
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("my.collection.empty")
    }

    private var shouldShowCollectedSection: Bool {
        school == nil && filter == .all && !pinnedOnly && !collectedLibrary.records.isEmpty
    }

    private var isLoadingCollectedSection: Bool {
        shouldShowCollectedSection && (collectedLibrary.isLoading ||
            (collectedLibrary.items.isEmpty && collectedLibrary.unavailableRecords.isEmpty))
    }

    private var collectedSection: some View {
        let cardWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 180 : 112
        let cardHeight = cardWidth * 156 / 112
        let cardShape = RoundedRectangle(cornerRadius: 10)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App Clip에서 수집한 카드")
                    .font(.custom("Paperlogy-8ExtraBold", size: 19, relativeTo: .headline))
                Spacer()
                if isLoadingCollectedSection {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("App Clip 카드 불러오는 중")
                }
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(collectedLibrary.items) { item in
                        Button { selectedCollectedCard = item } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                VStack {
                                    Text(item.story.cucumberName).font(.headline).lineLimit(2)
                                    Text(item.story.content).font(.caption).lineLimit(5)
                                }
                                .padding(10)
                                .frame(width: cardWidth, height: cardHeight)
                                .background(CampusStyle.lightGreen.opacity(0.3), in: cardShape)
                                .clipShape(cardShape)
                                Text(item.story.cucumberName)
                                    .font(.custom("Paperlogy-8ExtraBold", size: 15, relativeTo: .caption))
                                    .foregroundStyle(.black)
                                    .lineLimit(2)
                            }
                            .frame(width: cardWidth, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.story.cucumberName) 수집 카드")
                    }

                    ForEach(collectedLibrary.unavailableRecords) { _ in
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.title3)
                            Text("연결 대기").font(.caption).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color(.secondarySystemBackground), in: cardShape)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("서버 연결을 기다리는 수집 카드")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, 16)
    }

    private func collectedCardImage(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            @unknown default:
                Color.clear
            }
        }
        .frame(width: 112, height: 156)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.16), radius: 3, x: 1, y: 2)
    }

    private var sortBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { sortChoices; countBadge }
            } else {
                HStack(spacing: 7) { sortChoices; countBadge }
            }
        }
    }

    private var sortChoices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { sortButtons }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) { sortButtons }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var sortButtons: some View {
        ForEach(MYCardSort.allCases, id: \.self) { option in
            Button { sort = option } label: {
                Text(option.rawValue).font(.custom(sort == option ? "Paperlogy-5Medium" : "Paperlogy-4Regular", size: 16, relativeTo: .body))
                    .foregroundStyle(sort == option ? .white : .black)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(sort == option ? CampusStyle.lightGreen : Color(.systemGray5), in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(sort == option ? .isSelected : [])
            .accessibilityIdentifier("my.sort.\(option)")
        }
        Button { pinnedOnly.toggle() } label: {
            Image(systemName: "pin.fill").font(.system(size: 14, weight: .bold))
                .foregroundStyle(pinnedOnly ? .white : .black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(pinnedOnly ? CampusStyle.lightGreen : Color(.systemGray5), in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("고정한 카드만 보기")
            .accessibilityAddTraits(pinnedOnly ? .isSelected : []).accessibilityIdentifier("my.pinned")
        Button {} label: {
            Text("MY")
                .font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .body))
                .tracking(-0.56)
                .foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .frame(minWidth: 47, minHeight: 29)
                .background(Color(white: 231 / 255), in: Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("MY 필터")
        .accessibilityIdentifier("my.collection.myFilter")
    }

    private var countBadge: some View {
        Text(showsFolders ? "\(schools.count)학교" : "\(cards.count)개")
            .font(.custom(cards.isEmpty ? "Paperlogy-6SemiBold" : "Paperlogy-5Medium", size: 16, relativeTo: .body))
            .foregroundStyle(cards.isEmpty ? CampusStyle.green : .white)
            .padding(.horizontal, 16).padding(.vertical, 5)
            .background(cards.isEmpty ? .clear : CampusStyle.green, in: Capsule())
            .accessibilityIdentifier("my.collection.count")
    }

    private var cardGrid: some View {
        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                  ? [GridItem(.adaptive(minimum: 150), spacing: 10)]
                  : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(cards) { card in
                VStack(spacing: 0) {
                    Button { selectedCard = card } label: {
                        MYCardArtwork(card: card)
                            .shadow(color: .black.opacity(0.4), radius: 5)
                    }
                    .buttonStyle(.plain).accessibilityLabel("\(card.title) 카드 확대")
                    .accessibilityIdentifier("my.card.\(card.id)")

                }
            }
        }.padding(.bottom, 12)
    }

    private var schoolFolders: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
            ForEach(sortedSchools) { school in
                NavigationLink(value: MYDestination.school(school)) {
                    VStack(spacing: 10) {
                        MYSchoolFolder(cards: demo.collectionCards(school: school, sort: sort, pinnedOnly: pinnedOnly))
                        Text(school.rawValue).font(.custom("Paperlogy-6SemiBold", size: 25, relativeTo: .title2))
                            .foregroundStyle(Color(red: 0.41, green: 0.31, blue: 0.13))
                    }
                }.buttonStyle(.plain).accessibilityLabel("\(school.rawValue), 수집 카드 \(demo.collectionCards(school: school, sort: sort, pinnedOnly: pinnedOnly).count)개")
                    .accessibilityIdentifier("my.school.\(school.id)")
            }
        }
    }

    private var sortedSchools: [MYSchool] {
        let orderedCards = demo.collectionCards(school: nil, sort: sort, pinnedOnly: pinnedOnly)
        return schools.sorted { first, second in
            (orderedCards.firstIndex { $0.school == first } ?? .max) < (orderedCards.firstIndex { $0.school == second } ?? .max)
        }
    }

    private var collectionFilters: some View {
        HStack(spacing: 6) {
            ForEach([MYCollectionFilter.all, .schools], id: \.self) { option in
                Button {
                    demo.collectionFilter = option
                    if school != nil { dismiss() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 20, weight: .bold))
                        Text(option.rawValue).font(.custom("Paperlogy-5Medium", size: 12, relativeTo: .caption))
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(filter == option ? CampusStyle.green : Color(.darkGray))
                    .background(filter == option ? Color(red: 0.92, green: 0.94, blue: 0.89).opacity(0.8) : Color(.systemGray5).opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityAddTraits(filter == option ? .isSelected : [])
                    .accessibilityIdentifier("my.filter.\(option)")
            }
        }.frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 186).padding(.bottom, 6)
            .frame(maxWidth: .infinity).padding(.top, 8)

    }

    private func cardOverlay(_ card: MYCard) -> some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 32)
            let cardWidth = min(362, availableWidth)
            let cardHeight = cardWidth * 502 / 362
            let referenceScale = cardWidth / 362
            let pinWidth = max(44, 49 * referenceScale)

            ScrollView {
                VStack(spacing: 15) {
                    MYCardArtwork(card: card)
                        .frame(width: cardWidth, height: cardHeight)
                        .shadow(color: .black.opacity(0.25), radius: 3.5, x: 3, y: 6)
                        .accessibilityLabel("\(card.title), \(card.school.rawValue)의 카드")

                    HStack(spacing: 7) {
                        Button { detailCard = card; selectedCard = nil } label: {
                            Text("자세히 보기")
                                .font(.custom("Paperlogy-5Medium", size: 20, relativeTo: .headline))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 10)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("확대 화면을 닫고 카드 이야기를 엽니다")
                        .accessibilityIdentifier("my.card.details")

                        Button { demo.toggleFavorite(card) } label: {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(demo.favorites.contains(card.id) ? CampusStyle.green : .black)
                                .frame(width: pinWidth)
                                .frame(minHeight: 44)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(remote?.isBusy == true || remote?.needsReauthentication == true)
                        .accessibilityLabel("카드 고정 \(demo.favorites.contains(card.id) ? "해제" : "추가")")
                        .accessibilityAddTraits(demo.favorites.contains(card.id) ? .isSelected : [])
                        .accessibilityIdentifier("my.favorite.\(card.id)")
                    }
                    .frame(width: cardWidth)
                    .foregroundStyle(.black)
                    if let remote {
                        if remote.needsReauthentication { OiConnectionStatus(remote: remote) }
                        if let error = remote.error {
                            Text(error).font(.footnote).foregroundStyle(.white).frame(width: cardWidth)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .background(Color.black.opacity(0.88).ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                Button { selectedCard = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.white)
                .accessibilityLabel("카드 확대 닫기")
                .accessibilityIdentifier("my.card.close")
                .padding(12)
            }
            .accessibilityAction(.escape) { selectedCard = nil }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }

    private func collectedCardOverlay(_ item: CollectedStoryLibraryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.story.cucumberName)
                    .font(.custom("Paperlogy-8ExtraBold", size: 28, relativeTo: .title))
                Text(item.story.content)
                    .font(.body)
                if let remote {
                    Button("내 계정 도감에 저장") {
                        guard let owner = remote.account?.id else { return }
                        Task {
                            guard remote.account?.id == owner, !remote.needsReauthentication, !remote.isBusy else { return }
                            await remote.perform("collect", payload: ["id": item.story.id])
                            if remote.account?.id == owner,
                               remote.collections.contains(where: { $0.storyId.uuidString.caseInsensitiveCompare(item.story.id) == .orderedSame }),
                               collectedLibrary.removeImported(storyID: item.story.id) {
                                selectedCollectedCard = nil
                            }
                        }
                    }.disabled(remote.account == nil || remote.isBusy || remote.needsReauthentication)
                    if remote.needsReauthentication { OiConnectionStatus(remote: remote) }
                    if let error = remote.error { Text(error).foregroundStyle(.red) }
                    if let error = collectedLibrary.persistenceError { Text(error).foregroundStyle(.red) }
                }
                Text("수집일 \(item.record.collectedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct MYSchoolFolder: View {
    let cards: [MYCard]

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 171
            ZStack(alignment: .topLeading) {
                Image("MYFolderBack").resizable().frame(width: 171 * scale, height: 228 * scale)
                ForEach(Array(cards.prefix(3).reversed().enumerated()), id: \.element.id) { index, card in
                    MYCardArtwork(card: card)
                        .frame(width: 147 * scale, height: 204 * scale)
                        .shadow(color: .black.opacity(0.25), radius: 3.5 * scale, x: 3 * scale, y: 6 * scale)
                        .offset(x: [18, 12, 6][index] * scale, y: [9, 5, 12][index] * scale)
                }
                Image("MYFolderFront").resizable().frame(width: 187 * scale, height: 201.3 * scale)
                    .offset(x: -8 * scale, y: 30.7 * scale)
                HStack(alignment: .bottom, spacing: 3 * scale) {
                    Text("\(cards.count)")
                        .font(.custom("Paperlogy-7Bold", size: 50 * scale, relativeTo: .title))
                        .tracking(2 * scale).frame(height: 35 * scale)
                    Text("card")
                        .font(.custom("Paperlogy-4Regular", size: 25 * scale, relativeTo: .title2))
                        .tracking(0.5 * scale).frame(height: 16 * scale)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 45.34 * scale, alignment: .bottom)
                .foregroundStyle(Color(red: 105 / 255, green: 79 / 255, blue: 33 / 255))
                .offset(x: 15.954 * scale, y: 159.523 * scale)
            }.frame(width: geometry.size.width, height: 228 * scale)
                .mask { Image("MYFolderMask").resizable() }
        }.aspectRatio(171 / 228, contentMode: .fit).dynamicTypeSize(.medium).accessibilityHidden(true)
    }
}

struct MYCardStoryView: View {
    let card: MYCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MYCardArtwork(card: card).frame(maxHeight: 502)
                    .frame(maxWidth: .infinity).accessibilityLabel("\(card.title) 카드")
                Text(card.title).font(CampusStyle.heading(28))
                Text(card.school.rawValue).font(.headline)
                Text(card.body)
                    .font(.body).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("카드 이야기").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).toolbarRole(.navigationStack)
    }
}

#Preview("도감 · Reference", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack {
        MYCollectionView(demo: MYLibraryStore(), storyRepository: AppContainer.preview.storyRepository)
    }
}

#Preview("도감 · Small", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack {
        MYCollectionView(demo: MYLibraryStore(), storyRepository: AppContainer.preview.storyRepository)
    }
}

#Preview("도감 · Large", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack {
        MYCollectionView(demo: MYLibraryStore(), storyRepository: AppContainer.preview.storyRepository)
    }
}
