import SwiftUI
import RealityKit

struct ARCameraView: UIViewRepresentable {
    let controller: ARSessionController
    func makeCoordinator() -> ARSessionController { controller }
    func makeUIView(context: Context) -> RealityKit.ARView { controller.view }
    func updateUIView(_ uiView: RealityKit.ARView, context: Context) {}
    static func dismantleUIView(_ uiView: RealityKit.ARView, coordinator: ARSessionController) {
        coordinator.stop()
    }
}
