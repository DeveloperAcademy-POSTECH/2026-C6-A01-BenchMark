import SwiftUI

struct CampusSummaryView: View {
    let story: CampusStory
    let store: CampusStoryStore
    var isCameraCoverActive = false
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(440, geometry.size.width - 40,
                                max(200, (geometry.size.height - 180) * 362 / 502))
            ScrollView {
            // Figma `5400:5071`: info card at y 113 from the screen top, postcard at y 226 (26pt below the card).
            VStack(spacing: 26) {
                NavigationLink(value: CampusDestination.story(story.id)) { information }
                    .buttonStyle(.plain).accessibilityIdentifier("campus.details")
                CampusPostcard(story: story, store: store)
                    .frame(width: cardWidth).accessibilityIdentifier("campus.summary.card")
                if let id = UUID(uuidString: story.id), let count = remote?.continuationCounts[id] {
                    Text("이어진 이야기 \(count)개 · 공개된 이야기 연결이에요")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("campus.summary.continuationCount")
                }
                if story.isExample { CampusExampleBadge() }
            }.padding(.horizontal, 20).padding(.top, 113).padding(.bottom, 105)
                .frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden).ignoresSafeArea(edges: .top)
        }.background(.white)
            .overlay(alignment: .bottom) {
                bottomBar.frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea(edges: .bottom)
            }
            .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
            // The story form offers the five most recently opened stories as donations to continue from (#411).
            // Also runs when the account finishes loading, so a story opened right after launch is not missed.
            .task(id: "\(remote?.continuationPrivacyKey ?? "public")/\(remote?.revision ?? 0)") {
                if let remote, let id = UUID(uuidString: story.id), !story.isExample {
                    try? await remote.refreshContinuationCounts(for: [id])
                }
                if let owner = remote?.account?.id, !story.isExample {
                    OiRecentStories.record(story.id, owner: owner)
                }
            }
    }

    /// Figma `하단 버튼` (`5400:5165`): 93pt tall including the home indicator, two 175×46 buttons 20pt from the top.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Continues to the story list (#399).
                Button { store.openStoryListAction?() } label: {
                    Text("이어서 기부하기").font(CampusStyle.medium(16)).tracking(0.32)
                        .foregroundStyle(.black).frame(maxWidth: .infinity, minHeight: 46)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).disabled(store.openStoryListAction == nil)
                    .accessibilityIdentifier("campus.summary.continue")
                CampusCollectButton(story: story, store: store).frame(maxWidth: .infinity)
            }.padding(.horizontal, 20).padding(.top, 20)
            Spacer(minLength: 0)
        }
        .frame(height: 93)
        .background {
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25).fill(.white.opacity(0.4))
                UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25).fill(CampusStyle.mapSheet)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: -1)
            }.compositingGroup().clipShape(Rectangle().inset(by: -8).offset(y: -8))
        }
    }
    /// Figma "오이 정보"(5400:5173): name with the trailing "오이" in green, tags, three info lines and a chevron.
    private var information: some View {
        let name = story.title
        let hasSuffix = name.hasSuffix("오이") && name.count > 2
        let lead = hasSuffix ? String(name.dropLast(2)) : name
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Text(lead).foregroundStyle(.black))\(Text(hasSuffix ? "오이" : "").foregroundStyle(Color(oiRGB: 0x65804E)))")
                    .font(ScratchPostcardFont.cucumberName).tracking(0.52)
                    .lineLimit(1).minimumScaleFactor(0.6).frame(minHeight: 31)
                HStack(spacing: 6) {
                    ForEach(story.tags.filter { !$0.isEmpty }, id: \.self) { tag in
                        HStack(spacing: 1) {
                            Text("#").tracking(-0.52)
                            Text(tag.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).tracking(0.26)
                        }
                    }
                }
                .font(CampusStyle.body(13)).foregroundStyle(Color(oiRGB: 0xA15C03)).lineLimit(1)
                .frame(minHeight: 16)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("| " + story.donor)
                Text("| " + story.location)
                Text("| " + story.date)
            }.font(CampusStyle.body(10)).tracking(0.2).lineLimit(1).minimumScaleFactor(0.8)
            // Always pinned to the trailing edge, whatever the text length (#399).
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.system(size: 16, weight: .bold)).tracking(0.32)
                .foregroundStyle(Color(oiRGB: 0x949494))
                .accessibilityHidden(true)
        }.foregroundStyle(.black).padding(.leading, 14).padding(.trailing, 16).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color(oiRGB: 0x1C3700).opacity(0.25), radius: 3.5)
    }
}
