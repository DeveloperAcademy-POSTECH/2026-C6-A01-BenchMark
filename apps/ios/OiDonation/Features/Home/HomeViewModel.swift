import Foundation
import Observation

@MainActor @Observable
final class HomeViewModel {
    enum State {
        case idle, loading, loaded(HomeDashboard), unavailable
    }
    private(set) var state: State = .idle
    private let repository: any HomeRepository
    var donorName: String {
        if case .loaded(let dashboard) = state { return dashboard.donorName }
        return "기부자"
    }
    init(repository: any HomeRepository) { self.repository = repository }
    func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            if let dashboard = try await repository.fetchDashboard() { state = .loaded(dashboard) }
            else { state = .unavailable }
        } catch is CancellationError { state = .idle }
        catch { state = .unavailable }
    }
}
