import Foundation

/// Replace the design fixture with school-confirmed data when the service is connected.
struct HomeDashboard: Sendable {
    var donorName: String
    var attachedBenchCount: Int
    var targetBenchCount: Int
    var participantCount: Int
    var progress: Int
    var isExample: Bool

}
