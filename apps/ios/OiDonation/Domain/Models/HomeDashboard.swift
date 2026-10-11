import Foundation

/// Replace the design fixture with school-confirmed data when the service is connected.
struct HomeDashboard: Sendable {
    var donorName: String
    var attachedBenchCount: Int
    var targetBenchCount: Int
    var participantCount: Int
    var progress: Int
    var isExample: Bool

    static let designExample = HomeDashboard(
        donorName: "김사과", attachedBenchCount: 17, targetBenchCount: 30,
        participantCount: 235, progress: 78, isExample: true
    )
}

