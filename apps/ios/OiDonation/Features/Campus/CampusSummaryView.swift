import SwiftUI

struct CampusSummaryView: View {
    let story: CampusStory
    let store: CampusStoryStore
    @State private var scene = CampusExploreScene()
    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CampusMapSurface(scene: scene).ignoresSafeArea().allowsHitTesting(false)
                if scene.isLoading { ProgressView().frame(maxHeight: .infinity, alignment: .top) }
                VStack(spacing: 12) {
                    hero.frame(maxHeight: .infinity)
                    summary.frame(height: min(380, max(340, geometry.size.height * 0.52)))
                }.padding(.horizontal, 11).padding(.bottom, 0)
            }
        }
        .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
        .task {
            await scene.load()
            if let region = CampusRegion.examples.first(where: { $0.id == story.regionID }) { scene.focusBackdrop(region) }
        }
        .onAppear { isOnScreen = true; scene.setVisible(scenePhase == .active) }
        .onDisappear { isOnScreen = false; scene.setVisible(false) }
        .onChange(of: scenePhase) { _, phase in scene.setVisible(isOnScreen && phase == .active) }
    }

    private var hero: some View {
        GeometryReader { geometry in
            HStack(spacing: -30) {
                Image(story.image).resizable().scaledToFit()
                    .frame(width: geometry.size.width * 0.75, height: geometry.size.height)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 16)
                if story.isCats {
                    NavigationLink(value: CampusDestination.story(story.id)) {
                        Image("OiStoryCard").resizable().scaledToFit().frame(width: geometry.size.width * 0.28)
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 4)
                    }.buttonStyle(.plain).accessibilityLabel("6냥이오이 카드와 이야기 자세히 보기")
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var summary: some View {
        VStack(spacing: 10) {
            Capsule().fill(Color(.systemGray4)).frame(width: 52, height: 5).padding(.top, 5)
            HStack(spacing: 5) {
                Text(story.title).font(CampusStyle.heading(30)).lineLimit(1).minimumScaleFactor(0.65)
                CampusDonorBadge(size: 14)
                Spacer(minLength: 2)
                CampusTags(story: story)
            }.padding(.horizontal, 19)
            Text("\(story.donor)  |  \(story.location)  |  \(story.date)")
                .font(CampusStyle.hand(10)).lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 19)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("“ \(story.excerpt)”").font(CampusStyle.hand(18)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 19)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(story.gallery, id: \.self) { name in
                        Image(name).resizable().scaledToFill().frame(width: name == "OiGallery01" ? 219 : 260, height: 146)
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    ForEach(story.remoteMediaPaths, id: \.self) { path in
                        OiStoryMediaImage(path: path) { path in
                            guard let resolver = store.mediaURL else { throw OiServiceError.unavailable }
                            return try await resolver(path)
                        }.frame(width: 260, height: 146).clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    if story.gallery.isEmpty && story.remoteMediaPaths.isEmpty { Text("첨부된 사진이 없어요").font(.subheadline).frame(width: 320, height: 146).background(CampusStyle.background(story.palette), in: RoundedRectangle(cornerRadius: 20)) }
                }.padding(.horizontal, 10)
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                NavigationLink(value: CampusDestination.story(story.id)) {
                    Text("자세히보기").font(CampusStyle.body(11)).foregroundStyle(.black).frame(width: 106, height: 46)
                        .background(CampusStyle.action.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("campus.details")
                CampusCollectButton(story: story, store: store)
            }.padding(.horizontal, 10).padding(.bottom, 10)
        }
        .foregroundStyle(.black).background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 30))
    }
}
