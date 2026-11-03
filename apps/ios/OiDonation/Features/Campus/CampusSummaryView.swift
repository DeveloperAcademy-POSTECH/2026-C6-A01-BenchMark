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
                ScrollView {
                    VStack(spacing: 34) {
                        HStack(alignment: .center, spacing: -14) {
                            Image(story.portraitImage).resizable().scaledToFit().scaleEffect(1.18)
                                .frame(width: max(100, (geometry.size.width - 40) * 0.46), height: 307)
                                .accessibilityHidden(true)
                            summary.frame(maxWidth: .infinity)
                        }
                        NavigationLink(value: CampusDestination.story(story.id)) {
                            MYCardArtwork(card: MYCard(id: story.id, title: story.title, image: story.image,
                                school: .postech, order: story.order, body: story.body, donor: story.donor, date: story.date))
                                .frame(width: min(240, geometry.size.width * 0.60), height: 330)
                        }.buttonStyle(.plain).accessibilityLabel("오이 카드와 이야기 자세히 보기")
                        if !story.remoteMediaPaths.isEmpty {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(story.remoteMediaPaths, id: \.self) { path in
                                        OiStoryMediaImage(path: path) { path in
                                            guard let resolver = store.mediaURL else { throw OiServiceError.unavailable }
                                            return try await resolver(path)
                                        }.frame(width: 200, height: 160).clipped()
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }


                    }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
        }
        .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
        .task {
            await scene.load()
            if let region = CampusRegion.campus.first(where: { $0.id == story.regionID }) { scene.focusBackdrop(region) }
        }
        .onAppear { isOnScreen = true; scene.setVisible(scenePhase == .active) }
        .onDisappear { isOnScreen = false; scene.setVisible(false) }
        .onChange(of: scenePhase) { _, phase in scene.setVisible(isOnScreen && phase == .active) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text(story.title).font(CampusStyle.heading(28)).lineLimit(1).minimumScaleFactor(0.6)
                CampusTags(story: story)
                VStack(alignment: .leading, spacing: 6) {
                    Text("| " + story.donor)
                    Text("| " + story.location)
                    Text("| " + story.date)
                }.font(CampusStyle.body(11)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 16) {
                NavigationLink(value: CampusDestination.story(story.id)) {
                    Text("자세히보기").font(CampusStyle.body(16)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 43)
                        .background(CampusStyle.secondaryAction, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("campus.details")
                    .shadow(color: CampusStyle.green.opacity(0.35), radius: 4, y: 2)
                CampusCollectButton(story: story, store: store, fill: CampusStyle.summaryAction)
                    .shadow(color: CampusStyle.summaryAction.opacity(0.35), radius: 4, y: 2)
            }
        }.padding(20).foregroundStyle(.black)
            .background(.white, in: RoundedRectangle(cornerRadius: 30))
    }
}
