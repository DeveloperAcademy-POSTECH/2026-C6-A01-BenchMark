import SwiftUI
import CryptoKit
import RealityKit

/// The expensive look hash is calculated only when the wardrobe changes.
enum OiCardPortrait {
    static func key(for look: OiWardrobeLook, seed: OiSeedCucumberSnapshot?) -> String {
        guard let seedKey = seed?.portraitKey else { return key(for: look) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let colors = (try? encoder.encode(look.seedGarmentColors ?? [:])) ?? Data()
        return seedKey + "-colors-v1-" + SHA256.hash(data: colors).description
    }

    static func key(for look: OiWardrobeLook) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(look)) ?? Data()
        // Regenerate portraits when the selected model geometry or skin changes.
        let revision: String
        if look.costume == .sportswear {
            revision = "portrait-v7-raised-black-sportswear-eyes-"
        } else if look.costume == .schoolUniformTrousers {
            revision = "portrait-v6-clean-trouser-uniform-"
        } else if look.costume == .scientistGoggles {
            revision = "portrait-v6-clean-goggles-researcher-cloth-"
        } else if look.costume != nil {
            revision = "portrait-v5-clean-costume-faces-"
        } else if look.top == .postech {
            revision = "portrait-v6-original-postech-word-only-"
        } else if look.top == .cardigan && look.bottom == .shorts {
            revision = "portrait-v5-cardigan-shorts-fit-"
        } else {
            revision = "portrait-v4-bright4-skin-"
        }
        return "transparent-matte-v1-" + revision + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// While the size tab is open, one live scene stays mounted. Snapshots are taken
/// after movement settles; stale/cancelled captures cannot replace the latest pose.
extension OiSeedCucumberSnapshot {
    var portraitKey: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).map { "seed-v1-" + SHA256.hash(data: $0).description }
    }
}

struct OiCardPortraitCapture: View {
    let look: OiWardrobeLook
    var seed: OiSeedCucumberSnapshot? = nil
    let cacheKey: String
    var orientation = OiCardOrientation()
    var interactivePreview = false
    var placeholder: UIImage? = nil
    let onCapture: (Data, String) -> Void
    var onFailure: (() -> Void)? = nil
    @State private var scene = OiWardrobeScene()
    @State private var liveScene = OiWardrobeScene()
    @State private var failure = false
    @State private var attempt = 0
    @State private var completedCapture: String?
    private var captureID: String { "\(cacheKey)-\(attempt)" }
    var body: some View {
        ZStack {
            if interactivePreview {
                if liveScene.loading, let placeholder {
                    Image(uiImage: placeholder).resizable().scaledToFit().allowsHitTesting(false)
                }
                OiCardPortraitSurface(scene: liveScene, look: look, seed: seed, orientation: orientation)
                    .allowsHitTesting(false)
            }
            // Keep the capture surface mounted but visually hidden. Its black/white
            // passes must never flash in the interactive card placement preview.
            if !interactivePreview || completedCapture != captureID {
                OiCardPortraitSurface(scene: scene, look: look, seed: seed, orientation: orientation)
                    .opacity(interactivePreview ? 0.001 : 1).allowsHitTesting(false).accessibilityHidden(true)
            }
            if failure && !interactivePreview {
                Button("오이 이미지 다시 만들기") {
                    scene.update(look, retry: true, seed: seed); attempt += 1
                }.font(.caption).padding(10).background(.regularMaterial, in: Capsule())
            } else if !interactivePreview || scene.loading {
                ProgressView("꾸민 오이를 카드에 담는 중").font(.caption)
            }
        }
        .task(id: captureID) {
            failure = false
            // Keep the loaded model/materials while rotating; only the camera changes.
            scene.update(look, seed: seed)
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
                guard let image = await scene.cardPortrait(),
                      let data = await OiPortraitImages.shared.encode(image, key: cacheKey) else {
                    if !Task.isCancelled { failure = true; onFailure?() }; return
                }
                try Task.checkCancellation()
                onCapture(data, cacheKey)
                completedCapture = captureID
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
    let seed: OiSeedCucumberSnapshot?
    let orientation: OiCardOrientation
    func makeCoordinator() -> OiWardrobeScene { scene }
    func makeUIView(context: Context) -> RealityKit.ARView {
        let view = scene.install()
        scene.transparentCardBackground()
        scene.cardOrientation(orientation)
        scene.update(look, seed: seed)
        return view
    }
    func updateUIView(_ view: RealityKit.ARView, context: Context) {
        guard scene.isInstalled(view) else { return }
        scene.cardOrientation(orientation)
        scene.update(look, seed: seed)
    }
    static func dismantleUIView(_ view: RealityKit.ARView, coordinator: OiWardrobeScene) {
        coordinator.uninstall(view)
    }
}
