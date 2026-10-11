import SwiftUI

/// 카메라 위에 겹쳐 표시하는 조명 전용 패널입니다.
struct ARLiveAdjustmentPanel: View {
    @Bindable var controller: ARSessionController
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("조명").font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "chevron.down").frame(width: 44, height: 32)
                }.accessibilityLabel("조명 패널 접기")
            }
            ARLiveLightingPanel(controller: controller)
                .disabled(controller.loading || controller.capturing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}
