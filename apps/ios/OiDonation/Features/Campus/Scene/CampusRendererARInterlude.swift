// Created by 이돈혁

#if DEBUG
import ARKit
import RealityKit
import AVFoundation

/// Used only by the explicit -campus-renderer-check development launch argument.
@MainActor enum CampusRendererARInterlude {
    static func run(in window: UIWindow) async -> Bool {
        guard ARWorldTrackingConfiguration.isSupported,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return false
        }
        var view: RealityKit.ARView? = RealityKit.ARView(frame: window.bounds,
            cameraMode: .ar, automaticallyConfigureSession: false)
        window.addSubview(view!)
        view?.session.run(ARWorldTrackingConfiguration())
        try? await Task.sleep(for: .seconds(2))
        view?.session.pause()
        view?.scene.anchors.removeAll()
        view?.removeFromSuperview()
        view = nil
        try? await Task.sleep(for: .milliseconds(300))
        return true
    }
}
#endif
