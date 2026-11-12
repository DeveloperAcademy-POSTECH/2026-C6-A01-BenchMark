//
//  ARPostcardPrototypeFlowView.swift
//  OiDonationClip
//
//  Created by Jiwon Hong on 11/9/26.
//

#if DEBUG
import SwiftUI

/// Debug flow for #267: AR puzzle first, then the completed 2D postcard once.
/// Swapping the phase removes the AR view, whose coordinator stops the camera session and motion updates.
struct ARPostcardPrototypeFlowView: View {
    private enum Phase { case puzzle, postcard }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.puzzle

    var body: some View {
        ZStack {
            switch phase {
            case .puzzle:
                ARPostcardPrototypeView(onCompleted: showPostcard)
                    .transition(.opacity)
            case .postcard:
                ARPostcardResultView(postcard: .sample)
                    .transition(.opacity)
            }
        }
    }

    private func showPostcard() {
        guard phase == .puzzle else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            phase = .postcard
        }
    }
}
#endif
