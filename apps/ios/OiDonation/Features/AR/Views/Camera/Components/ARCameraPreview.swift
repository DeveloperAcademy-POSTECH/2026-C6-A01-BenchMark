import SwiftUI

struct ARCameraPreview: View {
    let controller: ARSessionController
    let recording: Bool
    var topInset: CGFloat = 0
    var body: some View {
        ZStack(alignment: .top) {
            ARCameraView(controller: controller, isActive: controller.ready)
                .saturation(controller.settings.photoFilter.saturation)
            VStack(spacing: 8) {
                if controller.isPalmMode {
                    Text(controller.locked ? "현재 위치 고정 · 잠금을 풀면 손을 다시 인식해요" : controller.message)
                        .font(.caption).multilineTextAlignment(.center)
                        .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("ar.camera.palmStatus")
                }
                if !controller.isPalmMode && !controller.usesGeographicPlacement && controller.recoveryIssue == nil && (!controller.placed || !controller.ready) {
                    Text(controller.message)
                        .font(.callout).multilineTextAlignment(.center)
                        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if controller.loading {
                    ProgressView().accessibilityLabel("캐릭터 불러오는 중…")
                        .padding(12).background(.regularMaterial, in: Capsule())
                }
            }
            .padding()
            .padding(.top, topInset)
            .opacity(recording ? 0 : 1)
            .allowsHitTesting(!recording)
        }
        .clipped()
    }

}
