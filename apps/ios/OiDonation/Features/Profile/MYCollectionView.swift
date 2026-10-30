// Created by 이돈혁

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    private var filter: MYCollectionFilter { demo.collectionFilter }
    private var cards: [MYCard] { demo.collectionCards(school: school, sort: sort, pinnedOnly: pinnedOnly) }
    private var showsFolders: Bool { filter == .schools && school == nil }
    private var schools: [MYSchool] {
        Array(Set(cards.map(\.school))).sorted { $0.name < $1.name }
    }

    init(
        demo: MYLibraryStore,
        school: MYSchool? = nil,
        storyRepository: any StoryRepository,
        remote: OiRemoteStore? = nil
    ) {
        self.demo = demo
        self.remote = remote
        self.school = school
        _collectedLibrary = State(
            initialValue: CollectedStoryLibrary(
                repository: storyRepository,
                collectionStore: StoryCollectionStore()
            )
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            sortBar
            if let remote { OiConnectionStatus(remote: remote) }
            ScrollView {
                if shouldShowCollectedSection {
                    collectedSection
                }
                if let remote, !remote.hasLoadedRemote {
                    if remote.loadError == nil { ProgressView("도감을 불러오는 중") }
                } else if showsFolders && !schools.isEmpty {
                    schoolFolders
                } else if cards.isEmpty {
                    ContentUnavailableView(pinnedOnly ? "즐겨찾는 오이가 없어요" : "아직 수집한 카드가 없어요", systemImage: pinnedOnly ? "pin" : "leaf", description: Text(pinnedOnly ? "카드 확대 화면의 핀을 눌러 이 화면에 모아보세요." : "로그인 후 캠퍼스의 공개 오이 이야기를 수집해 보세요."))
                        .padding(.top, 60)
                } else {
                    cardGrid
                }
            }.scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .background {
            if school != nil {
                Color(red: 186 / 255, green: 154 / 255, blue: 95 / 255).ignoresSafeArea()
            } else { Color(.systemBackground).ignoresSafeArea() }
        }
        .navigationTitle(school?.rawValue ?? "도감")
        .toolbar { ToolbarItem(placement: .principal) {
            Text(school?.rawValue ?? "도감").font(.custom("Paperlogy-6SemiBold", size: 30, relativeTo: .title))
                .foregroundStyle(Color(red: 117 / 255, green: 75 / 255, blue: 0))
        } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarRole(.navigationStack)
        .safeAreaInset(edge: .bottom) { collectionFilters }
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

    private var shouldShowCollectedSection: Bool {
        school == nil && filter == .all && !pinnedOnly && !collectedLibrary.records.isEmpty
    }

    private var collectedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App Clip에서 수집한 카드")
                    .font(.custom("Paperlogy-8ExtraBold", size: 19, relativeTo: .headline))
                Spacer()
                if collectedLibrary.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(collectedLibrary.items) { item in
                        Button { selectedCollectedCard = item } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                VStack { Text(item.story.cucumberName).font(.headline); Text(item.story.content).font(.caption).lineLimit(5) }.padding(10).frame(width: 112, height: 156).background(CampusStyle.lightGreen.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                                Text(item.story.cucumberName)
                                    .font(.custom("Paperlogy-8ExtraBold", size: 15, relativeTo: .caption))
                                    .foregroundStyle(.black)
                                    .lineLimit(2)
                            }
                            .frame(width: 112, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.story.cucumberName) 수집 카드")
                    }

                    ForEach(collectedLibrary.unavailableRecords) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            ContentUnavailableView("연결 대기", systemImage: "arrow.triangle.2.circlepath")
                                .frame(width: 112, height: 156)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            Text("스토리 \(record.storyID)")
                                .font(.caption)
                                .lineLimit(2)
                        }
                        .frame(width: 112, alignment: .leading)
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
            Text("내 계정에 저장한 카드")
                .font(.caption2).foregroundStyle(.secondary)

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
    }

    private var countBadge: some View {
        Text(showsFolders ? "\(schools.count)학교" : "\(cards.count)개")
            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 5).background(CampusStyle.green, in: Capsule())
            .accessibilityIdentifier("my.collection.count")
    }

    private var cardGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 104), spacing: 10)], spacing: 12) {
            ForEach(cards) { card in
                VStack(spacing: 0) {
                    Button { selectedCard = card } label: {
                        MYCardArtwork(card: card)
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 2, y: 3)
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
                        Text(option.rawValue).font(.custom("Pretendard-Bold", size: 12, relativeTo: .caption))
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(filter == option ? CampusStyle.green : Color(.darkGray))
                    .background(filter == option ? Color(red: 0.92, green: 0.94, blue: 0.89).opacity(0.8) : Color(.systemGray5).opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityAddTraits(filter == option ? .isSelected : [])
                    .accessibilityIdentifier("my.filter.\(option)")
            }
        }.frame(maxWidth: 186).padding(.bottom, 6)
            .frame(maxWidth: .infinity).padding(.top, 8)

    }

    private func cardOverlay(_ card: MYCard) -> some View {
        VStack(spacing: 15) {
            MYCardArtwork(card: card).accessibilityLabel("\(card.title), \(card.school.rawValue)의 카드")
            HStack(spacing: 7) {
                Button { detailCard = card; selectedCard = nil } label: {
                    Text("자세히 보기").font(.custom("Paperlogy-6SemiBold", size: 20, relativeTo: .headline))
                        .frame(maxWidth: .infinity, minHeight: 44).background(.white, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("my.card.details")
                Button { demo.toggleFavorite(card) } label: {
                    Image(systemName: "pin.fill").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(demo.favorites.contains(card.id) ? CampusStyle.green : .black)
                        .frame(width: 49, height: 44).background(.white, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("카드 고정 \(demo.favorites.contains(card.id) ? "해제" : "추가")")
                    .accessibilityIdentifier("my.favorite.\(card.id)")
            }.foregroundStyle(.black)
            Button("닫기") { selectedCard = nil }.frame(minHeight: 44)
        }.padding(20).presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
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
                        Task {
                            await remote.perform("collect", payload: ["id": item.story.id])
                            if remote.collections.contains(where: { $0.storyId.uuidString.caseInsensitiveCompare(item.story.id) == .orderedSame }) {
                                collectedLibrary.removeImported(storyID: item.story.id)
                                selectedCollectedCard = nil
                            }
                        }
                    }.disabled(remote.account == nil || remote.isBusy)
                    if let error = remote.error { Text(error).foregroundStyle(.red) }
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
                        .frame(width: 147.6 * scale, height: 204.7 * scale)
                        .offset(x: [20.7, 11.7, 6.5][index] * scale, y: [9.1, 5.2, 11.7][index] * scale)
                }
                Image("MYFolderFront").resizable().frame(width: 187 * scale, height: 201.3 * scale)
                    .offset(x: -8 * scale, y: 30.7 * scale)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(cards.count)").font(.custom("PearToucan-Regular", size: 50 * scale, relativeTo: .title))
                    Text("card").font(.system(size: 24 * scale))
                }.foregroundStyle(Color(red: 0.41, green: 0.31, blue: 0.13))
                    .position(x: 72 * scale, y: 198 * scale)
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

#Preview("도감") {
    NavigationStack {
        MYCollectionView(demo: MYLibraryStore(), storyRepository: AppContainer.preview.storyRepository)
    }
}
