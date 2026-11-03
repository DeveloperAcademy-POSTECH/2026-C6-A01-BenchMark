// Created by 이돈혁

import Foundation

@main
struct OiAccountConnectionFlowChecks {
    private enum Failure: Error { case assertion(String) }

    private struct AuthenticationProbe {
        let proof: OiSession
        private(set) var calls = 0
        mutating func signIn() -> OiSession { calls += 1; return proof }
    }

    static func main() {
        do {
            try existingAccountTransition()
            try newMethodFromMergeEntry()
            try representativeChange()
            try reviewChanged()
            try currentProofRefresh()
            try cancellation()
            print("PASS: shared account connection route preserves additional proof without reauthentication, new-method outcomes, representative changes, review conflicts, current-proof refresh, and cancellation isolation")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func existingAccountTransition() throws {
        var flow = OiAccountConnectionFlow(mode: .addLoginMethod)
        let current = session("current"), additional = session("additional")
        var provider = AuthenticationProbe(proof: additional)
        flow.acceptCurrentProof(current)
        flow.acceptAdditionalProof(provider.signIn())
        try require(!flow.hasClassifiedAdditional, "Provider authentication alone must not classify an account as blank")
        let operation = flow.operationID
        let originalProof = try encoded(additional)
        flow.resolvePreview(sourceIsNew: false)
        try require(flow.mode == .mergeExisting && flow.canChooseRepresentative, "Separate account did not transition to merge")
        try require(flow.operationID == operation, "Automatic route transition replaced the operation")
        try require(try encoded(flow.additionalProof) == originalProof, "Automatic route transition replaced the additional proof")
        flow.resolvePreview(sourceIsNew: false)
        try require(flow.operationID == operation && provider.calls == 1, "Preview transition requested another provider authentication")
    }

    private static func newMethodFromMergeEntry() throws {
        var flow = OiAccountConnectionFlow(mode: .mergeExisting)
        var provider = AuthenticationProbe(proof: session("new-method"))
        flow.acceptCurrentProof(session("current"))
        flow.acceptAdditionalProof(provider.signIn())
        let operation = flow.operationID
        flow.resolvePreview(sourceIsNew: true)
        try require(flow.mode == .addLoginMethod && !flow.canChooseRepresentative, "Blank source should use add-method confirmation")
        try require(flow.representative == .current, "New login method replaced the current representative")
        try require(!flow.chooseRepresentative(.additional), "New login method allowed a different representative")
        try require(flow.operationID == operation && provider.calls == 1, "New-method classification restarted authentication or operation")
    }

    private static func representativeChange() throws {
        var flow = OiAccountConnectionFlow()
        let current = session("current"), additional = session("existing")
        flow.acceptCurrentProof(current)
        flow.acceptAdditionalProof(additional)
        flow.resolvePreview(sourceIsNew: false)
        let operation = flow.operationID
        try require(flow.chooseRepresentative(.additional), "Existing accounts should allow choosing a representative")
        try require(flow.operationID != operation, "Representative change did not invalidate the old operation")
        flow.resolvePreview(sourceIsNew: true)
        try require(flow.mode == .mergeExisting && flow.representative == .additional, "Directional source counts changed the selected representative")
        try require(try encoded(flow.pair?.target) == encoded(additional), "Chosen target proof changed")
        try require(try encoded(flow.pair?.source) == encoded(current), "Chosen source proof changed")
    }

    private static func reviewChanged() throws {
        var flow = OiAccountConnectionFlow(mode: .addLoginMethod)
        var provider = AuthenticationProbe(proof: session("additional"))
        flow.acceptCurrentProof(session("current"))
        flow.acceptAdditionalProof(provider.signIn())
        flow.resolvePreview(sourceIsNew: true)
        let operation = flow.operationID
        let retained = try encoded(flow.additionalProof)
        flow.reviewChanged()
        try require(!flow.hasClassifiedAdditional, "Changed review retained a now-unconfirmed blank-account claim")
        try require(flow.operationID != operation && (try encoded(flow.additionalProof)) == retained, "Rolled-back review conflict discarded a valid proof")
        flow.resolvePreview(sourceIsNew: false)
        try require(flow.mode == .mergeExisting && provider.calls == 1, "A changed review requested another provider login")
    }

    private static func currentProofRefresh() throws {
        var flow = OiAccountConnectionFlow(mode: .addLoginMethod)
        var current = session("current")
        var provider = AuthenticationProbe(proof: session("additional"))
        flow.acceptCurrentProof(current)
        flow.acceptAdditionalProof(provider.signIn())
        flow.resolvePreview(sourceIsNew: false)
        _ = flow.chooseRepresentative(.additional)
        let operation = flow.operationID
        let retained = try encoded(flow.additionalProof)
        current = OiSession(accessToken: "refreshed-current-access", refreshToken: "refreshed-current-refresh",
                            expiresIn: 3600, expiresAt: Date().timeIntervalSince1970 + 3600, user: current.user)
        flow.acceptCurrentProof(current)
        try require(flow.operationID != operation, "Refreshing the current proof retained a preview bound to its old session")
        try require(try encoded(flow.additionalProof) == retained, "Refreshing only the current proof discarded the additional proof")
        try require(flow.representative == .additional && provider.calls == 1, "Refreshing current authentication restarted or changed the source")
        try require(try encoded(flow.pair?.source) == encoded(current), "Refreshed current proof was not used")
    }

    private static func cancellation() throws {
        let persistedAppSession = session("persisted-app-login")
        let original = try encoded(persistedAppSession)
        var flow = OiAccountConnectionFlow(mode: .addLoginMethod)
        flow.acceptCurrentProof(persistedAppSession)
        flow.acceptAdditionalProof(session("additional"))
        flow.resolvePreview(sourceIsNew: false)
        let operation = flow.operationID
        flow.clearProofs()
        try require(flow.currentProof == nil && flow.additionalProof == nil && flow.pair == nil, "Canceled flow kept authentication proofs")
        try require(flow.operationID != operation && flow.mode == .addLoginMethod, "Canceled flow did not reset to its entry mode")
        try require(try encoded(persistedAppSession) == original, "Clearing temporary proof state changed the app login")
    }

    private static func session(_ name: String) -> OiSession {
        OiSession(accessToken: "\(name)-access", refreshToken: "\(name)-refresh", expiresIn: 3600,
                  expiresAt: Date().timeIntervalSince1970 + 3600, user: OiAccount(id: UUID(), email: "\(name)@example.invalid"))
    }

    private static func encoded(_ value: OiSession?) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.assertion(message) }
    }
}
