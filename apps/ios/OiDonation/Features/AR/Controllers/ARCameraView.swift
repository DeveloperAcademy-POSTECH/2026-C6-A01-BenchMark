import SwiftUI
import RealityKit

struct ARCameraView: UIViewRepresentable {
    let controller: ARSessionController
    let isActive: Bool
    func makeCoordinator() -> ARSessionController { controller }
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {
        // Pausing ARSession stops camera frames, but an attached ARView still
        // submits Metal work. Keep its scene while detaching the render surface.
        if isActive {
            let renderer = controller.view
            if renderer.superview !== uiView {
                renderer.frame = uiView.bounds
                renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                uiView.addSubview(renderer)
            }
        } else {
            controller.view.removeFromSuperview()
        }
    }
    static func dismantleUIView(_ uiView: UIView, coordinator: ARSessionController) {
        coordinator.stop()
        coordinator.view.removeFromSuperview()
    }
}
