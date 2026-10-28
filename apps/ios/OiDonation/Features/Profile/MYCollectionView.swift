// Created by 이돈혁

import SwiftUI

struct MYCollectionView: View {
    let demo: MYDemoStore
    var school: MYSchool? = nil
    @State private var sort = CampusStorySort.latest
    @State private var selectedCard: MYDemoCard?
    @State private var detailCard: MYDemoCard?
    @State private var selectedDetail: MYDemoCard?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    private var filter: MYCollectionFilter { demo.collectionFilter }
    private var cards: [MYDemoCard] { demo.visibleCards(filter: filter, school: school, sort: sort) }
    private var showsFolders: Bool { filter == .schools && school == nil }

    var body: some View {
        VStack(spacing: 12) {
            sortBar
            ScrollView {
                if showsFolders {
                    schoolFolders
                } else if cards.isEmpty {
                    ContentUnavailableView("즐겨찾는 오이가 없어요", systemImage: "heart", description: Text("카드 옆 하트를 눌러 이 화면에 모아보세요."))
                        .padding(.top, 60)
                } else {
                    cardGrid
                }
            }.scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .background {
            if filter == .schools || school != nil {
                Image("MYCollectionPaper").resizable().ignoresSafeArea()
            } else { Color(.systemBackground).ignoresSafeArea() }
        }
        .navigationTitle(school?.rawValue ?? "도감")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarRole(.navigationStack)
        .safeAreaInset(edge: .bottom) { collectionFilters }
        .sheet(item: $selectedCard, onDismiss: {
            if let card = detailCard { detailCard = nil; selectedDetail = card }
        }) { card in
            cardOverlay(card)
        }
        .navigationDestination(item: $selectedDetail) { card in MYCardStoryView(card: card) }
    }

    private var sortBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { sortChoices; countBadge }
            } else {
                HStack(spacing: 7) { sortChoices; countBadge }
            }
            Text(sort == .distance ? "디자인 예시 · 가상 거리 기준" : "디자인 예시 · 실제 기부 내역이 아니에요")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var sortChoices: some View {
        ScrollView(.horizontal) { HStack(spacing: 7) { sortButtons } }
            .scrollIndicators(.hidden)
    }

    private var sortButtons: some View {
        ForEach(CampusStorySort.allCases, id: \.self) { option in
            Button { sort = option } label: {
                Text(option.rawValue).font(.custom("Pretendard-Regular", size: 16, relativeTo: .body))
                    .foregroundStyle(sort == option ? .white : .black)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(sort == option ? CampusStyle.lightGreen : Color(.systemGray5), in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(sort == option ? .isSelected : [])
            .accessibilityIdentifier("my.sort.\(option)")
        }
    }

    private var countBadge: some View {
        Text(showsFolders ? "\(MYSchool.allCases.count)학교" : "\(cards.count)개")
            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 5).background(CampusStyle.green, in: Capsule())
            .accessibilityIdentifier("my.collection.count")
    }

    private var cardGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 104), spacing: 10)], spacing: 12) {
            ForEach(cards) { card in
                VStack(spacing: 0) {
                    Button { selectedCard = card } label: {
                        Image(card.image).resizable().scaledToFit()
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 2, y: 3)
                    }
                    .buttonStyle(.plain).accessibilityLabel("\(card.title) 카드 확대")
                    .accessibilityIdentifier("my.card.\(card.id)")
                    HStack(spacing: 0) {
                        Text(card.title).font(.custom("Pretendard-Regular", size: 14, relativeTo: .caption))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { demo.toggleFavorite(card) } label: {
                            Image(systemName: demo.favorites.contains(card.id) ? "heart.fill" : "heart")
                                .foregroundStyle(demo.favorites.contains(card.id) ? CampusStyle.coral : .black)
                                .frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(card.title) 즐겨찾기 \(demo.favorites.contains(card.id) ? "해제" : "추가")")
                            .accessibilityIdentifier("my.favorite.\(card.id)")
                    }
                }
            }
        }.padding(.bottom, 12)
    }

    private var schoolFolders: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
            ForEach(sortedSchools) { school in
                NavigationLink(value: MYDestination.school(school)) {
                    VStack(spacing: 10) {
                        MYSchoolFolder(count: demo.cards.filter { $0.school == school }.count)
                        Text(school.rawValue).font(.custom("Pretendard-Regular", size: 24, relativeTo: .title2).bold())
                            .foregroundStyle(Color(red: 0.41, green: 0.31, blue: 0.13))
                    }
                }.buttonStyle(.plain).accessibilityLabel("\(school.rawValue), 예시 카드 \(demo.cards.filter { $0.school == school }.count)개")
                    .accessibilityIdentifier("my.school.\(school.id)")
            }
        }
    }

    private var sortedSchools: [MYSchool] {
        let orderedCards = demo.visibleCards(filter: .all, school: nil, sort: sort)
        return MYSchool.allCases.sorted { first, second in
            (orderedCards.firstIndex { $0.school == first } ?? .max) < (orderedCards.firstIndex { $0.school == second } ?? .max)
        }
    }

    private var collectionFilters: some View {
        HStack(spacing: 6) {
            ForEach(MYCollectionFilter.allCases, id: \.self) { option in
                Button {
                    demo.collectionFilter = option
                    if school != nil { dismiss() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 20, weight: .bold))
                        Text(option.rawValue).font(.custom("Pretendard-Regular", size: 12, relativeTo: .caption).bold())
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(filter == option ? CampusStyle.green : Color(.darkGray))
                    .background(filter == option ? Color(red: 0.92, green: 0.94, blue: 0.89).opacity(0.8) : Color(.systemGray5).opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityAddTraits(filter == option ? .isSelected : [])
                    .accessibilityIdentifier("my.filter.\(option)")
            }
        }.frame(maxWidth: 282).padding(.bottom, 6)
            .frame(maxWidth: .infinity).padding(.top, 8)
            .background(.regularMaterial)
    }

    private func cardOverlay(_ card: MYDemoCard) -> some View {
        VStack(spacing: 15) {
            Image(card.image).resizable().scaledToFit().accessibilityLabel("\(card.title), \(card.school.rawValue)의 디자인 예시 카드")
            Button { detailCard = card; selectedCard = nil } label: {
                Text("자세히 보기").font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44).background(.white, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("my.card.details")
            Button("닫기") { selectedCard = nil }.frame(minHeight: 44)
        }.padding(20).presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
    }
}

private struct MYSchoolFolder: View {
    let count: Int

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 171
            ZStack(alignment: .topLeading) {
                Image("MYFolderBack").resizable().frame(width: 171 * scale, height: 228 * scale)
                ForEach(Array(["MYFolderCardBack", "MYFolderCardMiddle", "MYBasicCard"].enumerated()), id: \.element) { index, name in
                    Image(name).resizable().scaledToFit()
                        .frame(width: 147.6 * scale, height: 204.7 * scale)
                        .offset(x: [20.7, 11.7, 6.5][index] * scale, y: [9.1, 5.2, 11.7][index] * scale)
                }
                Image("MYFolderFront").resizable().frame(width: 187 * scale, height: 201.3 * scale)
                    .offset(x: -8 * scale, y: 30.7 * scale)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(count)").font(CampusStyle.heading(42 * scale))
                    Text("card").font(.system(size: 24 * scale))
                }.foregroundStyle(Color(red: 0.41, green: 0.31, blue: 0.13))
                    .position(x: 72 * scale, y: 198 * scale)
            }.frame(width: geometry.size.width, height: 228 * scale)
                .mask { Image("MYFolderMask").resizable() }
        }.aspectRatio(171 / 228, contentMode: .fit).dynamicTypeSize(.medium).accessibilityHidden(true)
    }
}

struct MYCardStoryView: View {
    let card: MYDemoCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(card.image).resizable().scaledToFit().frame(maxHeight: 502)
                    .frame(maxWidth: .infinity).accessibilityLabel("\(card.title) 디자인 예시 카드")
                Text(card.title).font(CampusStyle.heading(28))
                Text(card.school.rawValue).font(.headline)
                Text("이 카드와 이야기는 MY 화면을 확인하기 위한 더미 데이터입니다. 실제 기부·증빙 승인·학교 납입 확인과 연결되지 않습니다.")
                    .font(.body).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("카드 이야기").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).toolbarRole(.navigationStack)
    }
}

#Preview("도감") { NavigationStack { MYCollectionView(demo: MYDemoStore()) } }
