//
//  CampusCucumberStoryView.swift
//  OiDonation
//
//  Created by Jiwon Hong on 11/16/26.
//

import SwiftUI
import MapKit

/// 오이 스토리 뷰 (Figma `5441:16811`): the cucumber and its information on top, and a tabbed sheet with
/// 이어진 기부 (`5919:11763`), 위치 (`5919:11840`) and 기부자 (`5919:11856`). Replaces the old story detail (#399).
struct CampusCucumberStoryView: View {
    let story: CampusStory
    let store: CampusStoryStore
    @State private var tab = Tab.related
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @Environment(\.dismiss) private var dismiss

    init(story: CampusStory, store: CampusStoryStore, initialTab: Tab = .related) {
        self.story = story
        self.store = store
        _tab = State(initialValue: initialTab)
    }

    enum Tab: Int, CaseIterable {
        case related, location, donor
        var title: String { ["이어진 기부", "위치", "기부자"][rawValue] }
        /// Figma tab fills: `#D3DBC4`, `#EAEEE2`, `#F1F4EC`.
        var fill: Color { [Color(oiRGB: 0xD3DBC4), Color(oiRGB: 0xEAEEE2), Color(oiRGB: 0xF1F4EC)][rawValue] }
    }

    var body: some View {
        GeometryReader { geometry in
            // Keep both information buttons visible on compact phones; longer text can still scroll.
            let compactPanelLimit = max(geometry.size.height * 0.35, geometry.size.height - 376)
            let panelHeight = min(457, geometry.size.height * 0.52, compactPanelLimit)
            VStack(spacing: 0) {
                top(height: geometry.size.height - panelHeight, width: geometry.size.width)
                CampusCucumberStoryPanel(story: story, store: store, tab: $tab)
                    .frame(height: panelHeight)
            }
        }
        .background(Color(oiRGB: 0xF0F0F0).ignoresSafeArea())
        .task(id: "\(story.id)/\(remote?.continuationPrivacyKey ?? "public")/\(remote?.revision ?? 0)") {
            if let remote, let id = UUID(uuidString: story.id) { try? await remote.refreshContinuationCounts(for: [id]) }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
        .toolbar {
            if let author = story.authorID, let id = UUID(uuidString: story.id) {
                ToolbarItem(placement: .topBarTrailing) {
                    OiStorySafetyButton(storyID: id, authorID: author, authorName: story.donor, onBlock: { dismiss() })
                }
            }
        }
    }

    /// Cucumber on the left (`5441:16814`, 158×315 at 22,72) and the white information card (`5441:16812`).
    private func top(height: CGFloat, width: CGFloat) -> some View {
        let portraitWidth = min(158, max(0, width - 22 - 7 - 209))
        return ScrollView {
            HStack(alignment: .top, spacing: 7) {
                CampusCucumberPortrait(story: story)
                    .frame(width: portraitWidth).frame(maxHeight: 315)
                    .padding(.leading, 22)
                information.frame(width: 209)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 72).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: height, alignment: .top)
    }

    private var information: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(story.title)
                        .font(ScratchPostcardFont.cucumberName).tracking(0.52)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        ForEach(story.tags.filter { !$0.isEmpty }, id: \.self) { tag in
                            HStack(spacing: 1) {
                                Text("#").tracking(-0.6)
                                Text(tag.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).tracking(0.3)
                            }
                        }
                    }
                    .font(CampusStyle.body(15)).foregroundStyle(Color(oiRGB: 0xA15C03)).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("| " + story.donor)
                    Text("| " + story.location)
                    Text("| " + story.date)
                }
                .font(CampusStyle.body(11)).tracking(0.22).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 16) {
                NavigationLink {
                    if let remote {
                        OiStoryListScreen(remote: remote,
                            continuation: OiStoryContinuationIntent(story: story, requestedBy: remote.account?.id))
                    }
                } label: {
                    Text("이어서 기부하기").font(CampusStyle.medium(16)).tracking(0.32)
                        .foregroundStyle(.black).frame(width: 169, height: 43)
                        .background(Color(oiRGB: 0xD3DBC4), in: RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color(oiRGB: 0x688633).opacity(0.9), radius: 2.5, x: 1, y: 1)
                }.buttonStyle(.plain).disabled(remote == nil)
                    .accessibilityIdentifier("campus.story.continue")
                CampusCollectButton(story: story, store: store)
                    .frame(width: 169, height: 43)
                    .shadow(color: Color(oiRGB: 0x243703).opacity(0.8), radius: 2.5, x: 1, y: 1)
            }
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 30))
    }
}

/// The 422pt-tall sheet with its three tabs (`분류 1·2·3`).
private struct CampusCucumberStoryPanel: View {
    let story: CampusStory
    let store: CampusStoryStore
    @Binding var tab: CampusCucumberStoryView.Tab

    private let tabWidth: CGFloat = 110
    private let tabHeight: CGFloat = 35

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Group {
                switch tab {
                case .related: CampusCucumberRelatedTab(story: story, store: store)
                case .location: CampusCucumberLocationTab(story: story)
                case .donor: CampusCucumberDonorTab(story: story, store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
        }
    }

    private var tabs: some View {
        ZStack(alignment: .topLeading) {
            // Paint the tabs back to front so each one's concave corner lies over the next tab.
            ForEach(Array(CampusCucumberStoryView.Tab.allCases.reversed()), id: \.rawValue) { item in
                let x = CGFloat(item.rawValue) * tabWidth
                UnevenRoundedRectangle(topLeadingRadius: 15, topTrailingRadius: 15)
                    .fill(item.fill).frame(width: tabWidth, height: tabHeight)
                    .offset(x: x)
                CampusStoryTabCorner().fill(item.fill).frame(width: 14, height: 14)
                    .offset(x: x + tabWidth, y: tabHeight - 14)
            }
            ForEach(CampusCucumberStoryView.Tab.allCases, id: \.rawValue) { item in
                Button { tab = item } label: {
                    Text(item.title).font(CampusStyle.medium(16)).foregroundStyle(Color(oiRGB: 0x273116))
                        .frame(width: tabWidth, height: tabHeight)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .offset(x: CGFloat(item.rawValue) * tabWidth)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).frame(height: tabHeight)
    }
}

/// Figma `Subtract`: the 14pt concave corner where a tab meets the sheet.
private struct CampusStoryTabCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let k: CGFloat = 0.5523
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                      control1: CGPoint(x: rect.maxX - rect.width * k, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * k))
        path.closeSubpath()
        return path
    }
}

// MARK: - 이어진 기부 (`5919:11763`)

private struct CampusCucumberRelatedTab: View {
    let story: CampusStory
    let store: CampusStoryStore

    var body: some View {
        if let parent = UUID(uuidString: story.id) { OiContinuationList(parent: parent, store: store) }
        else { ContentUnavailableView("아직 이어진 이야기가 없어요", systemImage: "link") }
    }
}

// MARK: - 위치 (`5919:11840`)

private struct CampusCucumberLocationTab: View {
    let story: CampusStory
    @Environment(\.openURL) private var openURL

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = story.latitude, let longitude = story.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)))) {
                    Marker(story.title, coordinate: coordinate).tint(.red)
                }
                .allowsHitTesting(false)
                .accessibilityLabel("저장한 위치: \(story.location)")
            } else {
                Color(oiRGB: 0xDCEAF1)
                Text("등록된 위치가 없어요.").font(CampusStyle.body(14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let coordinate {
                Button { openURL(directionsURL(to: coordinate)) } label: {
                    Text("구글맵 길찾기").font(CampusStyle.medium(16)).foregroundStyle(.black)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 30))
                }.buttonStyle(.plain).padding(.trailing, 25).padding(.bottom, 20)
            }
        }
    }

    private func directionsURL(to coordinate: CLLocationCoordinate2D) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [.init(name: "api", value: "1"),
                                 .init(name: "destination", value: "\(coordinate.latitude),\(coordinate.longitude)")]
        return components.url!
    }
}

// MARK: - 기부자 (`5919:11856`)

private struct CampusCucumberDonorTab: View {
    let story: CampusStory
    let store: CampusStoryStore
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var authorID: UUID? {
        guard !story.isExample, let id = story.authorID, !OiContentSafetyStore.shared.isBlocked(id) else { return nil }
        return id
    }

    var body: some View {
        GeometryReader { geometry in
            let showsFarmer = authorID != nil && !dynamicTypeSize.isAccessibilitySize
            let profileWidth = max(0, showsFarmer ? geometry.size.width * 0.52 - 30 : geometry.size.width - 60)
            ZStack(alignment: .topLeading) {
                if showsFarmer {
                    Ellipse().fill(RadialGradient(colors: [.black.opacity(0.25), .clear], center: .center,
                                                  startRadius: 0, endRadius: 108))
                        .frame(width: 216, height: 42).position(x: 294, y: 353)
                    MYPublicFarmerArtwork(asset: story.donorFarmerAsset)
                        .frame(width: 264, height: 352).offset(x: 155, y: 22)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 2) {
                                Image(systemName: "person.crop.circle.fill")
                                Text("공개 프로필")
                            }.font(CampusStyle.body(14)).tracking(0.28).foregroundStyle(Color(oiRGB: 0x9D9D9D))
                            Text(story.donor)
                                .font(.custom("Paperlogy-7Bold", size: 26, relativeTo: .title)).tracking(0.52)
                                .foregroundStyle(Color(oiRGB: 0x2C2C2C)).padding(.top, 7)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 10) {
                                chip("기부횟수")
                                chip("이어진 기부 횟수", count: UUID(uuidString: story.id).flatMap { remote?.continuationCounts[$0] })
                            }.padding(.top, 17)
                            Text("이어진 횟수는 공개된 이야기 연결 수이며 실제 납입 내역이 아니에요.")
                                .font(CampusStyle.body(12)).foregroundStyle(.secondary).padding(.top, 10)
                        }
                        .frame(width: profileWidth, alignment: .leading)
                        .padding(.leading, 30).padding(.top, 48)
                        Spacer(minLength: 24)
                        if let authorID, let remote {
                            NavigationLink {
                                MYPublicWorkshopView(authorID: authorID, remote: remote, store: store)
                            } label: {
                                Text("작성자 자세히 보기 →").underline().font(CampusStyle.semibold(16))
                                    .foregroundStyle(CampusStyle.green)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 30).padding(.bottom, 50)
                            .accessibilityIdentifier("campus.story.donor.details")
                        }
                    }.frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        }
    }

    private func chip(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title).font(CampusStyle.medium(15)).foregroundStyle(Color(oiRGB: 0x5D5D5D))
            Text(count.map { "\($0)" } ?? "—").font(CampusStyle.semibold(15)).foregroundStyle(Color(oiRGB: 0x708C40))
        }.tracking(0.3).padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color(oiRGB: 0xEAEEE2), in: Capsule())
            .accessibilityElement(children: .ignore).accessibilityLabel(count.map { "\(title): 공개된 이야기 \($0)개" } ?? "\(title): 집계 준비 중")
    }
}
