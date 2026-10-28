import SwiftUI

struct ARCameraPreview: View {
    let controller: ARSessionController
    let recording: Bool
    var topInset: CGFloat = 0
    var body: some View {
        ZStack(alignment: .top) {
            ARCameraView(controller: controller)
                .saturation(controller.settings.photoFilter.saturation)
            VStack(spacing: 8) {
                Text(controller.tracking)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                if controller.recoveryIssue == nil && (!controller.placed || !controller.ready) {
                    Text(controller.message)
                        .font(.callout).multilineTextAlignment(.center)
                        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if controller.settings.background == .stadium && !controller.backgroundMessage.isEmpty {
                    Text(controller.backgroundMessage)
                        .font(.caption).multilineTextAlignment(.center)
                        .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    if !controller.selectingBench && !controller.backgroundReady {
                        Text("사진 설정에서 벤치를 다시 선택해 주세요.").font(.caption)
                    }
                }
                if controller.loading {
                    ProgressView("캐릭터 불러오는 중…")
                        .padding(12).background(.regularMaterial, in: Capsule())
                }
            }
            .padding()
            .padding(.top, topInset)
            .allowsHitTesting(false)
            .opacity(recording ? 0 : 1)
        }
        .clipped()
    }

}
