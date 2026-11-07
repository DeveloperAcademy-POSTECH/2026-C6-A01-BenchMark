//
//  OiSampleMapView.swift
//  OiDonation / OiDonationClip
//
//  Created by Codex on 11/7/26.
//

import SwiftUI

/// Offline Figma backdrop with interactive sample markers. No location or network request.
struct OiSampleMapView: View {
    @State var isExpanded = false
    @State private var sort: CampusStorySort = .latest
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stories: [CampusStory] {
        CampusStoryExamples.stories.sorted { sort == .oldest ? $0.order > $1.order : $0.order < $1.order }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                OiSampleMapBackdrop()
                markers(in: geometry.size)
                VStack(spacing: 12) {
                    if typeSize.isAccessibilitySize {
                        Text("체험 이야기").font(.headline).padding(8).background(.regularMaterial, in: Capsule())
                    } else {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { isExpanded.toggle() }
                    } label: {
                        Label(isExpanded ? "목록닫기" : "목록보기", systemImage: isExpanded ? "xmark" : "list.star")
                            .font(CampusStyle.body(16)).padding(.horizontal, 20).padding(.vertical, 10)
                            .background(.white, in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("sample.toggleList")
                    }
                    list
                        .frame(height: isExpanded || typeSize.isAccessibilitySize
                               ? max(200, geometry.size.height - 64) : geometry.size.height * 0.43)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .foregroundStyle(.black)
    }

    private var list: some View {
        VStack(spacing: 20) {
            let headerLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            headerLayout {
                if typeSize.isAccessibilitySize {
                    Picker("정렬", selection: $sort) {
                        Text("최신순").tag(CampusStorySort.latest)
                        Text("오래된순").tag(CampusStorySort.oldest)
                    }.pickerStyle(.menu).fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("sample.sort")
                } else {
                ForEach([CampusStorySort.latest, .oldest], id: \.self) { option in
                    Button { sort = option } label: {
                        Text(option.rawValue).font(CampusStyle.body(16)).padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(sort == option ? .white : .black)
                            .background(sort == option ? CampusStyle.lightGreen : .white, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(sort == option ? .isSelected : [])
                        .accessibilityIdentifier(option == .latest ? "sample.sort.latest" : "sample.sort.oldest")
                }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("\(stories.count)개").font(CampusStyle.body(16)).foregroundStyle(CampusStyle.sectionGreen)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(CampusStyle.secondaryAction, in: Capsule())
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(stories) { story in
                        NavigationLink(value: CampusDestination.summary(story.id)) {
                            CampusStoryRow(story: story)
                        }.buttonStyle(.plain).accessibilityIdentifier("sample.row.\(story.id)")
                    }
                }.padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }.padding(20)
            .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 35, topTrailingRadius: 35))
    }

    private func markers(in size: CGSize) -> some View {
        // Relative positions describe artwork anchored to the Figma map, not flowing text.
        let decorations: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("OiSampleGraduate", 0.40, 0.09, 48), ("OiSampleGardener", 0.54, 0.16, 56),
            ("OiSamplePirate", 0.68, 0.19, 56), ("OiSampleTraveler", 0.88, 0.15, 47),
            ("OiSampleRaincoat", 0.10, 0.22, 63), ("OiSampleAstronaut", 0.12, 0.44, 82)
        ]
        return ZStack {
            ForEach(decorations.indices, id: \.self) { i in
                let item = decorations[i]
                Image(item.0).resizable().scaledToFit().frame(height: item.3)
                    .shadow(color: .white, radius: 8)
                    .position(x: size.width * item.1, y: size.height * item.2)
                    .accessibilityHidden(true)
            }
            ForEach(Array(CampusStoryExamples.stories.enumerated()), id: \.element.id) { index, story in
                let positions: [(CGFloat, CGFloat)] = [(0.47, 0.35), (0.89, 0.49), (0.65, 0.40)]
                NavigationLink(value: CampusDestination.summary(story.id)) {
                    Image(story.id == "example-makgeolli" ? "OiSampleMakgeolli" : story.portraitImage)
                        .resizable().scaledToFit().frame(width: 67, height: 89)
                        .shadow(color: .white, radius: 10)
                }.buttonStyle(.plain).accessibilityLabel("\(story.title) 예시 보기")
                    .accessibilityIdentifier("sample.marker.\(story.id)")
                    .position(x: size.width * positions[index].0, y: size.height * positions[index].1)
            }
        }.opacity(isExpanded || typeSize.isAccessibilitySize ? 0.25 : 1)
            .allowsHitTesting(!isExpanded && !typeSize.isAccessibilitySize)
            .accessibilityHidden(isExpanded || typeSize.isAccessibilitySize)
    }
}

struct OiSampleMapBackdrop: View {
    var isSummary = false
    var body: some View {
        GeometryReader { geometry in
            if isSummary {
                let scale = geometry.size.width / 402
                Image("OiSampleSummaryMap").resizable().scaledToFill()
                    .frame(width: 1199 * scale, height: 1858 * scale).clipped()
                    .offset(x: -434 * scale, y: -337 * scale)
            } else {
                Image("OiSampleMap").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct OiSampleSummaryView: View {
    let story: CampusStory
    let onCollect: () -> Void
    @State private var showingCard = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OiSampleMapBackdrop(isSummary: true)
                ScrollView {
                    VStack(spacing: 34) {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12))
                            : AnyLayout(HStackLayout(spacing: -14))
                        layout {
                            Image(story.portraitImage).resizable().scaledToFit().scaleEffect(1.18)
                                .frame(width: max(100, (geometry.size.width - 40) * 0.46), height: typeSize.isAccessibilitySize ? 190 : 307)
                                .accessibilityHidden(true)
                            summary
                        }
                        Button { showingCard = true } label: {
                            OiSampleStoryCard(story: story).frame(width: min(240, geometry.size.width * 0.60))
                        }.buttonStyle(.plain).accessibilityLabel("오이 카드 확대 보기")
                            .accessibilityIdentifier("sample.summary.card")
                    }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingCard) {
            OiSampleArtworkSheet(title: story.title + " · 예시 카드") { OiSampleStoryCard(story: story) }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(story.title).font(CampusStyle.characterTitle(28)).accessibilityAddTraits(.isHeader)
                CampusTags(story: story)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("| " + story.donor)
                Text("| " + story.location)
                Text("| " + story.date)
            }.font(CampusStyle.body(11)).fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: CampusDestination.story(story.id)) {
                Text("스토리 보기").font(CampusStyle.body(16)).frame(maxWidth: .infinity, minHeight: 44)
                    .background(CampusStyle.secondaryAction, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).accessibilityIdentifier("sample.details")
            OiSampleCollectButton(story: story, onCollect: onCollect)
        }.padding(20).foregroundStyle(.black).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 30))
    }
}

struct OiSampleCollectButton: View {
    let story: CampusStory
    let onCollect: () -> Void
    var body: some View {
        Button(action: onCollect) {
            Text(story.id == OiSampleStory.id ? "수집하기" : "6냥이 AR 체험")
                .font(CampusStyle.semibold(16)).frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 3).foregroundStyle(.white)
                .background(CampusStyle.summaryAction, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("sample.startAR")
    }
}

struct OiSampleStoryCard: View {
    let story: CampusStory
    var body: some View {
        if story.id == OiSampleStory.id {
            Image("OiCatsExampleCard").resizable().scaledToFit().accessibilityLabel("6냥이오이 디자인 예시 카드")
        } else {
            OiStoryCardArtwork(name: story.title, introduction: "체험용 예시", donor: story.donor,
                date: story.date, tags: story.tags, assetName: story.image)
        }
    }
}

struct OiSampleArtworkSheet<Artwork: View>: View {
    let title: String
    @ViewBuilder let artwork: () -> Artwork
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            artwork().padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }.preferredColorScheme(.light)
    }
}
