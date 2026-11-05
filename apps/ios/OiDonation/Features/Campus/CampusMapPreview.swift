#if DEBUG
import SwiftUI

/// Isolated design fixture. No server transport, evidence, or collection writes.
struct CampusMapPreviewHost: View {
    @State private var store = CampusStoryStore()
    @State private var library = MYLibraryStore()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(container: .pilot, store: store, myDemo: library, isCameraCoverActive: false,
                     onOpenProfile: { path.append(MYDestination.workshop) },
                     onOpenStory: { path.append(CampusDestination.summary($0)) })
            .navigationDestination(for: CampusDestination.self) { destination in
                switch destination {
                case .summary(let id):
                    if let story = store.story(id) { CampusSummaryView(story: story, store: store) }
                case .story(let id):
                    if let story = store.story(id) { CampusStoryDetailView(story: story, store: store) }
                }
            }
        }
        .tint(.black).preferredColorScheme(.light)
        .task {
            let counts = [10, 14, 4, 26, 4, 6]
            let fixtures = CampusRegion.campus.enumerated().flatMap { regionIndex, region in
                (0..<counts[regionIndex]).map { index in
                    CampusStory(id: "design-\(region.id)-\(index)", regionID: region.id,
                        title: index.isMultiple(of: 2) ? "새싹오이" : "이야기오이", image: "OiCats", tags: ["즐거움", "우정"],
                        donor: "디자인 확인용 예시 \(index + 1)", location: region.title,
                        date: "2026년 11월 3일 (화)", order: regionIndex * 100 + index, popularity: 0,
                        palette: index % 3, remoteBody: "디자인과 화면 이동을 확인하기 위한 가상의 이야기입니다.")
                }
            }
            store.synchronize(stories: fixtures, collected: [])
        }
    }
}

#Preview { CampusMapPreviewHost() }
#endif
