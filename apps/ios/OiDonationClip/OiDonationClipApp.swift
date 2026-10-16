import SwiftUI

@main
struct OiDonationClipApp: App {
    var body: some Scene {
        WindowGroup {
            if let configuration = try? ClipConfiguration.configured() {
                ContentView(configuration: configuration)
            } else {
                ContentUnavailableView("서비스 연결 준비 중", systemImage: "network.slash",
                    description: Text(ClipError.configuration.localizedDescription))
            }
        }
    }
}
