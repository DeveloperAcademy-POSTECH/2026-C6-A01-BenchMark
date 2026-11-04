import Foundation
import Observation

/// Discards responses from a dismissed screen or a previous account.
@MainActor @Observable
final class OiOperatorAccess {
    enum State: Equatable { case checking, allowed, denied, failed }
    private(set) var state: State = .checking
    private var requestID = UUID()

    func invalidate() {
        requestID = UUID()
        state = .checking
    }

    func check(using verify: () async throws -> Bool) async {
        let request = UUID()
        requestID = request
        // Periodic revalidation preserves navigation while the request is pending.
        if state != .allowed { state = .checking }
        do {
            let allowed = try await verify()
            try Task.checkCancellation()
            guard requestID == request else { return }
            state = allowed ? .allowed : .denied
        } catch {
            guard requestID == request else { return }
            state = Task.isCancelled || OiServiceFailure.isCancellation(error) ? .checking : .failed
        }
    }
}
