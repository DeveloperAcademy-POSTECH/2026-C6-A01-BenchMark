import SwiftUI

struct CampusSummaryView: View {
    let story: CampusStory
    let store: CampusStoryStore
    var isCameraCoverActive = false
    @State private var scene = CampusExploreScene()
    @State private var isOnScreen = false
    @State private var showingCard = false
    @State private var mapLoadAttempt = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CampusMapSurface(scene: scene).ignoresSafeArea().allowsHitTesting(false)
                if scene.isLoading { ProgressView().frame(maxHeight: .infinity, alignment: .top) }
                ScrollView {
                    VStack(spacing: 34) {
                        let expanded = dynamicTypeSize.isAccessibilitySize
                        let summaryLayout = expanded ? AnyLayout(VStackLayout(spacing: 12))
                            : AnyLayout(HStackLayout(alignment: .center, spacing: -14))
                        summaryLayout {
                            Image(story.portraitImage).resizable().scaledToFit().scaleEffect(1.18)
                                .frame(width: max(100, (geometry.size.width - 40) * 0.46), height: expanded ? 190 : 307)
                                .accessibilityHidden(true)
                            summary.frame(maxWidth: .infinity)
                        }
                        Button { showingCard = true } label: {
                            CampusStoryCardArtwork(story: story)
                                .frame(width: min(240, geometry.size.width * 0.60))
                        }.buttonStyle(.plain).accessibilityLabel("오이 카드 확대 보기")
                            .accessibilityIdentifier("campus.summary.card")
                        if story.isExample {
                            Text("디자인 예시로, 실제 기부·수집 기록에 포함되지 않아요.")
                                .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
                        }
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
        .fullScreenCover(isPresented: $showingCard) {
            CampusArtworkOverlay(title: story.title + " 카드") {
                CampusStoryCardArtwork(story: story)
            }
        }
        .overlay(alignment: .top) {
            if let error = scene.error {
                VStack(spacing: 8) {
                    Text(error).font(.footnote)
                    Button("지도 다시 불러오기") { mapLoadAttempt += 1 }
                        .buttonStyle(.bordered).disabled(scene.isLoading)
                }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
            }
        }
        .task(id: mapLoadAttempt) {
            await scene.load()
            if let region = CampusRegion.campus.first(where: { $0.id == story.regionID }) { scene.focusBackdrop(region) }
        }
        .onAppear { isOnScreen = true; scene.setVisible(!isCameraCoverActive && scenePhase == .active) }
        .onDisappear { isOnScreen = false; scene.suspendForARCamera() }
        .onChange(of: scenePhase) { _, phase in
            scene.setVisible(isOnScreen && !isCameraCoverActive && phase == .active)
        }
        .onChange(of: isCameraCoverActive) { _, active in
            if active { scene.suspendForARCamera() }
            else { scene.setVisible(isOnScreen && scenePhase == .active) }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                if story.isExample { CampusExampleBadge() }
                VStack(alignment: .leading, spacing: 5) {
                    Text(story.title).font(CampusStyle.characterTitle(28)).tracking(1.12)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    CampusTags(story: story)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("| " + story.donor)
                    Text("| " + story.location)
                    Text("| " + story.date)
                }.font(CampusStyle.body(11)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 16) {
                NavigationLink(value: CampusDestination.story(story.id)) {
                    Text("스토리 보기").font(CampusStyle.body(16)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 43)
                        .background(CampusStyle.secondaryAction, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("campus.details")
                    .shadow(color: CampusStyle.green.opacity(0.35), radius: 4, y: 2)
                CampusCollectButton(story: story, store: store)
                    .shadow(color: CampusStyle.summaryAction.opacity(0.35), radius: 4, y: 2)
            }
        }.padding(20).foregroundStyle(.black)
            .background(.white, in: RoundedRectangle(cornerRadius: 30))
    }
}
