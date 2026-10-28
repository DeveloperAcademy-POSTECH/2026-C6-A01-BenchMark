//
//  ARGameCameraView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import ARKit
import RealityKit
import SwiftUI

struct ARGameCameraView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.isLightEstimationEnabled = true
        configuration.environmentTexturing = .automatic
        view.session.run(configuration)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }
}
