import Foundation
import Observation

@Observable @MainActor
final class AppClipViewModel {
    enum State { case waiting, loading, ready, failed(String) }
    private(set) var state: State = .waiting
    private(set) var story: ClipStory?
    let client: ClipContentClient
    let configuration: ClipConfiguration

    init(configuration: ClipConfiguration) {
        self.configuration = configuration
        client = ClipContentClient(configuration: configuration)
    }

    func load(_ url: URL?) async {
        story = nil
        guard let url else { state = .waiting; return }
        state = .loading
        do {
            let route = try ClipRoute.parse(url, host: configuration.publicHost)
            let result = try await client.story(for: route)
            try Task.checkCancellation()
            story = result
            state = .ready
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed((error as? LocalizedError)?.errorDescription ?? "연결을 확인하고 다시 시도해 주세요.")
        }
    }
}
