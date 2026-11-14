import SwiftUI
import CryptoKit
import RealityKit

/// The expensive look hash is calculated only when the wardrobe changes.
enum OiCardPortrait {
    static func key(for look: OiWardrobeLook) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(look)) ?? Data()
        // Regenerate this outfit's portraits after its hem and shorts geometry update.
        let revision: String
        if look.costume != nil {
            revision = "portrait-v1-"
        } else if look.top == .cardigan && look.bottom == .shorts {
            revision = "portrait-v5-cardigan-shorts-fit-"
        } else {
            revision = "portrait-v4-bright4-skin-"
        }
        return revision + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// While the size tab is open, one live scene stays mounted. Snapshots are taken
/// after movement settles; stale/cancelled captures cannot replace the latest pose.
struct OiCardPortraitCapture: View {
    let look: OiWardrobeLook
    let cacheKey: String
    var orientation = OiCardOrientation()
    var interactivePreview = false
    let onCapture: (Data, String) -> Void
    var onFailure: (() -> Void)? = nil
    @State private var scene = OiWardrobeScene()
    @State private var failure = false
    @State private var attempt = 0
    var body: some View {
        ZStack {
            OiCardPortraitSurface(scene: scene, look: look, orientation: orientation)
                .allowsHitTesting(false)
            if failure && !interactivePreview {
                Button("오이 이미지 다시 만들기") {
                    scene.update(look, retry: true); attempt += 1
                }.font(.caption).padding(10).background(.regularMaterial, in: Capsule())
            } else if !interactivePreview || scene.loading {
                ProgressView("꾸민 오이를 카드에 담는 중").font(.caption)
            }
        }
        .task(id: "\(cacheKey)-\(attempt)") {
            failure = false
            // Keep the loaded model/materials while rotating; only the camera changes.
            scene.update(look)
            do {
                try await Task.sleep(for: .milliseconds(180))
                for _ in 0..<200 {
                    try Task.checkCancellation()
                    if !scene.loading { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try Task.checkCancellation()
                // Allow RealityKit to render the complete assembly at its current angle.
                try await Task.sleep(for: .milliseconds(100))
                guard let image = await scene.cardPortrait(), let data = image.pngData() else {
                    if !Task.isCancelled { failure = true; onFailure?() }; return
                }
                try Task.checkCancellation()
                onCapture(data, cacheKey)
            } catch { /* A newer angle or a closed tab superseded this capture. */ }
        }
        .accessibilityLabel("커스텀 오이 3D 미리보기")
    }
}

/// No built-in wardrobe gestures: the surrounding frame owns translation, pinch
/// and the two-finger orbit so one touch cannot accidentally rotate the model.
private struct OiCardPortraitSurface: UIViewRepresentable {
    let scene: OiWardrobeScene
    let look: OiWardrobeLook
    let orientation: OiCardOrientation
    func makeCoordinator() -> OiWardrobeScene { scene }
    func makeUIView(context: Context) -> RealityKit.ARView {
        let view = scene.install()
        scene.transparentCardBackground()
        scene.cardOrientation(orientation)
        scene.update(look)
        return view
    }
    func updateUIView(_ view: RealityKit.ARView, context: Context) {
        guard scene.isInstalled(view) else { return }
        scene.cardOrientation(orientation)
        scene.update(look)
    }
    static func dismantleUIView(_ view: RealityKit.ARView, coordinator: OiWardrobeScene) {
        coordinator.uninstall(view)
    }
}
