// Created by 이돈혁

import Foundation

@main
struct ARRecoveryChecks {
    static func main() {
        checkRecoveryActions()
        checkPendingAndRunningDeduplication()
        checkPauseInvalidatesAuthorization()
        checkResumeDuringOlderAuthorization()
        checkFailureResetSurvivesPauseAndDeniedStart()
        checkOrdinaryResumeCannotConsumeRecovery()
        checkInterruptionAndClosedCallbacks()
        print("PASS: recovery actions, start deduplication, stale authorization, restart after pause, failed-session reset, explicit recovery, interruption lifecycle")
    }

    private static func checkRecoveryActions() {
        let terminalIssues: [ARRecoveryIssue] = [.unsupported, .cameraRestricted]
        for issue in terminalIssues {
            precondition(!issue.canRetry && !issue.canOpenSettings)
            precondition(!issue.title.isEmpty && !issue.message.isEmpty)
        }
        precondition(ARRecoveryIssue.cameraDenied.canOpenSettings)
        precondition(!ARRecoveryIssue.cameraDenied.canRetry)
        let recoverable: [ARRecoveryIssue] = [.interrupted, .sessionFailure("session"), .characterLoadFailure("model")]
        for issue in recoverable {
            precondition(issue.canRetry && !issue.canOpenSettings)
        }
        precondition(Set((terminalIssues + recoverable + [.cameraDenied]).map(\.id)).count == 6)
        precondition(ARRecoveryIssue.sessionFailure("specific failure").message.contains("specific failure"))
        precondition(ARRecoveryIssue.characterLoadFailure("missing model").message.contains("missing model"))
    }

    private static func checkPendingAndRunningDeduplication() {
        var lifecycle = ARSessionLifecycle()
        guard let first = lifecycle.beginStart() else { preconditionFailure("Initial start must be accepted") }
        precondition(lifecycle.starting && !lifecycle.running)
        precondition(lifecycle.beginStart() == nil, "Concurrent permission requests must share the current attempt")
        precondition(lifecycle.completeStart(first))
        precondition(lifecycle.running && !lifecycle.starting)
        precondition(lifecycle.beginStart() == nil, "A healthy running session must be reused")
        precondition(!lifecycle.completeStart(first), "A completed start cannot be consumed twice")
    }

    private static func checkPauseInvalidatesAuthorization() {
        var lifecycle = ARSessionLifecycle()
        guard let pending = lifecycle.beginStart() else { preconditionFailure() }
        lifecycle.pause()
        precondition(!lifecycle.isCurrent(pending))
        precondition(!lifecycle.completeStart(pending), "Permission granted after close must not restart the camera")
        precondition(!lifecycle.rejectStart(pending), "An old denial must not replace the closed state")
        precondition(!lifecycle.starting && !lifecycle.running && !lifecycle.acceptsSessionCallbacks)
    }

    private static func checkResumeDuringOlderAuthorization() {
        var lifecycle = ARSessionLifecycle()
        guard let older = lifecycle.beginStart() else { preconditionFailure() }
        lifecycle.pause()
        guard let newer = lifecycle.beginStart() else { preconditionFailure("An outstanding older prompt must not drop the new start") }
        precondition(older != newer)
        precondition(!lifecycle.completeStart(older))
        precondition(!lifecycle.rejectStart(older))
        precondition(lifecycle.isCurrent(newer) && lifecycle.starting)
        precondition(lifecycle.completeStart(newer))
        precondition(lifecycle.running)
    }

    private static func checkFailureResetSurvivesPauseAndDeniedStart() {
        var lifecycle = ARSessionLifecycle()
        guard let initial = lifecycle.beginStart() else { preconditionFailure() }
        precondition(!initial.requiresTrackingReset)
        precondition(lifecycle.completeStart(initial))
        precondition(lifecycle.fail())
        precondition(!lifecycle.running && !lifecycle.acceptsSessionCallbacks)
        precondition(!lifecycle.fail(), "Repeated failure callbacks must not reopen recovery")
        lifecycle.pause()
        guard let denied = lifecycle.beginStart() else { preconditionFailure() }
        precondition(denied.requiresTrackingReset)
        precondition(lifecycle.rejectStart(denied))
        precondition(!lifecycle.acceptsSessionCallbacks)
        guard let recovered = lifecycle.beginStart() else { preconditionFailure() }
        precondition(recovered.requiresTrackingReset, "A permission denial must not consume the required AR reset")
        precondition(lifecycle.completeStart(recovered))
        lifecycle.pause()
        guard let resumed = lifecycle.beginStart() else { preconditionFailure() }
        precondition(!resumed.requiresTrackingReset, "Ordinary background resume must retain placement")
    }

    private static func checkOrdinaryResumeCannotConsumeRecovery() {
        var failed = ARSessionLifecycle()
        guard let initial = failed.beginStart() else { preconditionFailure() }
        precondition(failed.completeStart(initial))
        precondition(failed.fail())
        precondition(failed.beginStart() == nil, "Recorder drain must not consume a failed session without explicit retry")
        guard let retry = failed.beginStart(recovering: true) else { preconditionFailure("Explicit retry must recover a failed session") }
        precondition(retry.requiresTrackingReset)
        precondition(failed.completeStart(retry))
        precondition(failed.beginStart(recovering: true) == nil, "Explicit retries must still reuse a healthy running session")

        var interrupted = ARSessionLifecycle()
        guard let running = interrupted.beginStart() else { preconditionFailure() }
        precondition(interrupted.completeStart(running))
        precondition(interrupted.interrupt())
        precondition(interrupted.beginStart() == nil, "Recorder drain must preserve the interruption until ARKit ends it or the user retries")
        guard let resumed = interrupted.beginStart(recovering: true) else { preconditionFailure("Explicit retry must recover an interrupted session") }
        precondition(!resumed.requiresTrackingReset, "Interruption recovery must retain placement")
        precondition(interrupted.completeStart(resumed))
        precondition(!interrupted.endInterruption(), "A stale interruption-ended callback must not restart an explicit retry")
    }

    private static func checkInterruptionAndClosedCallbacks() {
        var lifecycle = ARSessionLifecycle()
        precondition(!lifecycle.interrupt() && !lifecycle.endInterruption() && !lifecycle.fail())
        guard let initial = lifecycle.beginStart() else { preconditionFailure() }
        precondition(!lifecycle.fail(), "Callbacks cannot mutate an unauthorized starting session")
        precondition(lifecycle.completeStart(initial))
        precondition(lifecycle.interrupt())
        precondition(!lifecycle.running && lifecycle.acceptsSessionCallbacks)
        precondition(!lifecycle.interrupt())
        precondition(lifecycle.endInterruption() && lifecycle.running)
        precondition(!lifecycle.endInterruption())
        precondition(lifecycle.interrupt())
        lifecycle.pause()
        precondition(!lifecycle.endInterruption(), "A closed view must not resume from an interruption callback")
        precondition(!lifecycle.fail() && !lifecycle.interrupt())
        guard let restarted = lifecycle.beginStart() else { preconditionFailure() }
        precondition(!restarted.requiresTrackingReset, "Interruption alone does not discard the world map")
        precondition(lifecycle.completeStart(restarted))
        precondition(lifecycle.interrupt())
        precondition(lifecycle.fail(), "Failure while interrupted must require explicit recovery")
        precondition(!lifecycle.endInterruption(), "Interruption-ended cannot clear a failed session")
    }
}
