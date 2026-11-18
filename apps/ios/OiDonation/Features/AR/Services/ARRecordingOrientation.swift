import UIKit

final class ARRecordingOrientation: NSObject, UIApplicationDelegate {
    static let mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.mask
    }

    static func lock(to window: UIWindow) {
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    static func unlock() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        }
    }
}
