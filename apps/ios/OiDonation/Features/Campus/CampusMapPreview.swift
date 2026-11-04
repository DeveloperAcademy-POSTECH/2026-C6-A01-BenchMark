#if DEBUG
import SwiftUI

/// Isolated design fixture. No server transport, evidence, or collection writes.
struct CampusMapPreviewHost: View {
    @State private var store = CampusStoryStore()
    @State private var library = MYLibraryStore()
    @State private var path = NavigationPath()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let example = arguments.contains("-campus-summary-preview") || arguments.contains("-campus-story-preview")
        _store = State(initialValue: CampusStoryStore(isExample: example))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.isExample {
                    if let first = store.stories.first {
                        if ProcessInfo.processInfo.arguments.contains("-campus-story-preview") {
                            CampusStoryDetailView(story: first, store: store)
                        } else {
                            CampusSummaryView(story: first, store: store)
                        }
                    } else {
                        ProgressView("디자인 예시 준비 중")
                    }
                } else {
                    HomeView(container: .pilot, store: store, myDemo: library, isCameraCoverActive: false,
                             onCamera: {}, onOpenProfile: { path.append(MYDestination.workshop) },
                             onOpenStory: { path.append(CampusDestination.summary($0)) })
                }
            }
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
            if store.isExample {
                store.synchronize(stories: CampusStoryExamples.stories, collected: [])
                return
            }
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
