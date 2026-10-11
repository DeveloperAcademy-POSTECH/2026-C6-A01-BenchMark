import SwiftUI

struct ARCaptureModePicker: View {
    @Binding var videoMode: Bool
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                modes
            }
        } else {
            modes
        }
    }

    private var modes: some View {
        HStack(spacing: 8) {
            mode("사진", isVideo: false)
            mode("비디오", isVideo: true)
        }
        .padding(4)
        .background(.white.opacity(0.04), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("촬영 모드")
    }

    private func mode(_ title: String, isVideo: Bool) -> some View {
        let selected = videoMode == isVideo
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                videoMode = isVideo
            }
        } label: {
            if selected {
                if #available(iOS 26, *) {
                    modeLabel(title, selected: true)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("capture-mode", in: selection)
                } else {
                    modeLabel(title, selected: true)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            } else {
                modeLabel(title, selected: false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(isVideo ? "마이크 음성을 포함한 비디오 촬영" : "사진 촬영")
    }

    private func modeLabel(_ title: String, selected: Bool) -> some View {
        // 레이블 자체에 글래스 효과를 적용하면 SwiftUI가 내용을 글래스 표면 위에 표시합니다.
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(selected ? Color.yellow : Color.white.opacity(0.85))
            .frame(minWidth: 68, minHeight: 44)
            .contentShape(Capsule())
    }

}
