import SwiftUI

struct CampusSummaryView: View {
    let story: CampusStory
    let store: CampusStoryStore
    var isCameraCoverActive = false
    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(440, geometry.size.width - 40,
                                max(200, (geometry.size.height - 180) * 362 / 502))
            ScrollView {
            VStack(spacing: 28) {
                NavigationLink(value: CampusDestination.story(story.id)) { information }
                    .buttonStyle(.plain).accessibilityIdentifier("campus.details")
                CampusPostcard(story: story, store: store)
                    .frame(width: cardWidth).accessibilityIdentifier("campus.summary.card")
                if story.isExample { CampusExampleBadge() }
            }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }.background(.white)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // Figma `5400:5071`: continues to the story list (#399).
                    Button { store.openStoryListAction?() } label: {
                        Text("이어서 기부하기").font(CampusStyle.medium(16))
                            .foregroundStyle(.black).frame(maxWidth: .infinity, minHeight: 46)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).disabled(store.openStoryListAction == nil)
                        .accessibilityIdentifier("campus.summary.continue")
                    CampusCollectButton(story: story, store: store).frame(maxWidth: .infinity)
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
                    .background(CampusStyle.mapSheet, in: UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25))
            }
            .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
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
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    ForEach(story.tags.filter { !$0.isEmpty }, id: \.self) { tag in
                        HStack(spacing: 1) {
                            Text("#").tracking(-0.52)
                            Text(tag.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).tracking(0.26)
                        }
                    }
                }
                .font(CampusStyle.body(13)).foregroundStyle(Color(oiRGB: 0xA15C03)).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("| " + story.donor)
                Text("| " + story.location)
                Text("| " + story.date)
            }.font(CampusStyle.body(10)).tracking(0.2).lineLimit(1).minimumScaleFactor(0.8)
            // Always pinned to the trailing edge, whatever the text length (#399).
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.system(size: 16, weight: .bold)).foregroundStyle(.gray)
                .accessibilityHidden(true)
        }.foregroundStyle(.black).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color(oiRGB: 0x1C3700).opacity(0.25), radius: 3.5)
    }
}
