import Foundation

@main
struct ArchitectureChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func main() async throws {
        require(Bench(id: "unknown", name: "Unknown", locationDescription: "Pending").coordinate == nil,
                "unconfirmed NFC location must remain absent")
        require(BenchCoordinate(latitude: 36.0139, longitude: 129.3232) != nil, "valid public location")
        for (latitude, longitude) in [(91.0, 0.0), (0.0, 181.0), (Double.nan, 0.0), (0.0, Double.infinity)] {
            require(BenchCoordinate(latitude: latitude, longitude: longitude) == nil, "invalid map coordinate rejected")
        }
        let parser = PublicLinkParser(allowedHost: "example.org")
        require(parser.parse(URL(string: "https://example.org/benches/bench-1")!) == .bench("bench-1"), "bench route")
        require(parser.parse(URL(string: "https://example.org/stories/plaque-1")!) == .story("plaque-1"), "story route")
        for url in ["http://example.org/benches/1", "https://evil.org/benches/1", "https://example.org/benches", "https://example.org/benches/1/extra", "https://user:password@example.org/stories/1"] {
            require(parser.parse(URL(string: url)!) == nil, "untrusted link must not route")
        }
        for draft in [ParticipationDraft(benchID: " ", message: "message", story: ""), ParticipationDraft(benchID: "bench", message: "\n ", story: "")] {
            do { _ = try draft.validated(); preconditionFailure("invalid draft accepted") }
            catch is ParticipationError { }
        }
        let draft = ParticipationDraft(benchID: " preview-bench ", message: " 응원합니다 \n", story: " 이야기 ")
        let repo = PreviewParticipationRepository()
        let key = UUID()
        async let first = repo.submit(draft, idempotencyKey: key)
        async let retry = repo.submit(draft, idempotencyKey: key)
        let (a, b) = try await (first, retry)
        require(a.id == b.id, "concurrent retry must not create duplicate")
        require(a.draft.message == "응원합니다", "normalize whitespace")
        require(a.applicationStatus == .submitted, "application submitted")
        require(a.verificationStatus == .awaitingSchoolConfirmation, "submission is not payment proof")
        require(a.plaqueStatus == nil, "submission must not start production")
        let applications = try await repo.fetchApplications()
        require(applications.count == 1, "one application for same key")
        do {
            _ = try await repo.submit(ParticipationDraft(benchID: "preview-bench", message: "다른 내용", story: ""), idempotencyKey: key)
            preconditionFailure("same key accepted changed payload")
        } catch ParticipationError.idempotencyConflict { }
        let offline = UnconnectedPilotRepository()
        let dashboard = try await offline.fetchDashboard()
        require(dashboard == nil, "missing API must not report invented statistics")
        do { _ = try await offline.submit(draft, idempotencyKey: UUID()); preconditionFailure("offline submit succeeded") }
        catch ParticipationError.serviceUnavailable { }
        let client = APIClient(approvedHost: "example.org")
        for endpoint in ["http://example.org/test", "https://evil.org/test", "https://user:pass@example.org/test"] {
            do {
                _ = try await client.send(URLRequest(url: URL(string: endpoint)!))
                preconditionFailure("untrusted endpoint was sent")
            } catch APIError.untrustedEndpoint { }
        }
        print("PASS: NFC coordinates, routing, validation, concurrent idempotency, pending verification and unavailable service")
    }
}
