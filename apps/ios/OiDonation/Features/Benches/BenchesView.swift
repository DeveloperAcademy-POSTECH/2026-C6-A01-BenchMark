import SwiftUI

struct BenchesView: View {
    let repository: any BenchRepository
    @State private var benches: [Bench] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    var body: some View {
        List {
            if isLoading { ProgressView() }
            else if let errorMessage { Text(errorMessage); Button("다시 확인") { Task { await load() } } }
            else if benches.isEmpty {
                ContentUnavailableView("벤치를 준비 중이에요", systemImage: "map",
                    description: Text("학교가 승인한 벤치와 위치가 준비되면 안내드립니다."))
            } else {
                ForEach(benches) { bench in
                    NavigationLink(value: PublicLinkParser.Destination.bench(bench.id)) {
                        VStack(alignment: .leading) { Text(bench.name); Text(bench.locationDescription).font(.caption) }
                    }
                }
            }
        }
        .navigationTitle("벤치지도").task { await load() }
    }
    private func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { benches = try await repository.fetchBenches() }
        catch is CancellationError { }
        catch { errorMessage = "벤치를 불러오지 못했어요." }
    }
}

struct PublicDestinationView: View {
    let destination: PublicLinkParser.Destination
    let benches: any BenchRepository
    let stories: any StoryRepository
    @State private var title = ""
    @State private var text = ""
    @State private var isLoading = true
    var body: some View {
        ScrollView {
            if isLoading { ProgressView() }
            else { VStack(alignment: .leading, spacing: 16) { Text(title).font(.title2); Text(text) }.padding(24) }
        }
        .navigationTitle("이야기 벤치").task(id: destination) {
            isLoading = true
            defer { isLoading = false }
            do {
                switch destination {
                case .bench(let id):
                    if let bench = try await benches.fetchBenches().first(where: { $0.id == id }) {
                        title = bench.name; text = bench.locationDescription
                    } else { title = "벤치를 확인할 수 없어요"; text = "공개된 벤치인지 확인해 주세요." }
                case .story(let id):
                    if let story = try await stories.fetchPublicStory(plaqueID: id) {
                        title = story.title; text = story.content
                    } else { title = "이야기를 확인할 수 없어요"; text = "삭제되었거나 아직 공개되지 않은 이야기입니다." }
                }
            } catch { title = "불러오지 못했어요"; text = "잠시 후 다시 시도해 주세요." }
        }
    }
}
