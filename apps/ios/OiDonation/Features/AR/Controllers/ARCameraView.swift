import SwiftUI
import RealityKit

struct ARCameraView: UIViewRepresentable {
    let controller: ARSessionController
    func makeUIView(context: Context) -> RealityKit.ARView { controller.view }
    func updateUIView(_ uiView: RealityKit.ARView, context: Context) {}
}
