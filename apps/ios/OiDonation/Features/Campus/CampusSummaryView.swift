import SwiftUI

struct CampusSummaryView: View {
    let story: CampusStory
    let store: CampusStoryStore
    var isCameraCoverActive = false
    @State private var showingDonation = false
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
                    Button { showingDonation = true } label: {
                        Text("이어서 기부하기").font(CampusStyle.medium(16))
                            .foregroundStyle(.black).frame(maxWidth: .infinity, minHeight: 46)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                    CampusCollectButton(story: story, store: store).frame(maxWidth: .infinity)
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
                    .background(CampusStyle.mapSheet, in: UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25))
            }
            .sheet(isPresented: $showingDonation) { HomeInformationSheet(destination: .donation) }
            .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
    }
    private var information: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(story.title).font(CampusStyle.characterTitle(26)).lineLimit(1).minimumScaleFactor(0.6)
                CampusTags(story: story, compact: true, size: 13)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("| " + story.donor)
                Text("| " + story.location)
                Text("| " + story.date)
            }.font(CampusStyle.body(10)).lineLimit(2)
            Image(systemName: "chevron.forward").font(.system(size: 16, weight: .bold)).foregroundStyle(.gray)
        }.foregroundStyle(.black).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color(oiRGB: 0x1C3700).opacity(0.25), radius: 3.5)
    }
}
