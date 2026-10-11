import SwiftUI

/// 카메라 옆이나 아래에 별도 공간을 차지해 AR 장면을 가리지 않습니다.
struct ARLiveAdjustmentPanel: View {
    @Bindable var controller: ARSessionController
    let close: () -> Void
    @State private var tab: Tab = .placement

    private enum Tab: String, CaseIterable, Identifiable {
        case placement = "배치", lighting = "조명"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("실시간 조절", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Button(action: close) {
                    Image(systemName: "chevron.down").frame(width: 44, height: 32)
                }.accessibilityLabel("실시간 조절 패널 접기")
            }
            ZStack(alignment: .top) {
                // 탭을 전환해도 촬영 영역이 유지되도록 두 조절 화면이 차지하는 공간을 유지합니다.
                LivePlacementPanel(controller: controller)
                    .opacity(tab == .placement ? 1 : 0)
                    .allowsHitTesting(tab == .placement)
                    .accessibilityHidden(tab != .placement)
                ARLiveLightingPanel(controller: controller)
                    .opacity(tab == .lighting ? 1 : 0)
                    .allowsHitTesting(tab == .lighting)
                    .accessibilityHidden(tab != .lighting)
            }
            .disabled(controller.capturing)
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

private struct LivePlacementPanel: View {
    @Bindable var controller: ARSessionController
    @State private var parameter: Parameter = .height

    private enum Parameter: String, CaseIterable, Identifiable {
        case height = "키", rotation = "회전", floorOffset = "바닥 높이"
        var id: Self { self }
    }

    private var value: Binding<Float> {
        switch parameter {
        case .height: $controller.settings.height
        case .rotation: $controller.settings.rotation
        case .floorOffset: $controller.settings.floorOffset
        }
    }

    private var range: ClosedRange<Float> {
        switch parameter {
        case .height: 0.2...2.5
        case .rotation: -180...180
        case .floorOffset: -0.3...0.3
        }
    }

    private var formattedValue: String {
        switch parameter {
        case .height: String(format: "%.2f m", value.wrappedValue)
        case .rotation: String(format: "%.0f°", value.wrappedValue)
        case .floorOffset: String(format: "%+.0f cm", value.wrappedValue * 100)
        }
    }

    private func resetParameter() {
        let defaults = ARCaptureSettings()
        switch parameter {
        case .height: value.wrappedValue = defaults.height
        case .rotation: value.wrappedValue = defaults.rotation
        case .floorOffset: value.wrappedValue = defaults.floorOffset
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("배치 조절 항목", selection: $parameter) {
                ForEach(Parameter.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Text(parameter.rawValue)
                Spacer()
                Text(formattedValue).monospacedDigit()
            }
            .font(.subheadline)
            .frame(minHeight: 31)
            Slider(value: value, in: range)
                .accessibilityLabel("캐릭터 \(parameter.rawValue)")
                .accessibilityValue(formattedValue)
            HStack {
                Text(controller.placed
                     ? "위치 잠금 중에도 키·회전·높이는 조절됩니다."
                     : "바닥을 터치해 캐릭터를 먼저 배치하세요.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("값 복원", action: resetParameter)
                    .font(.caption).buttonStyle(.bordered)
                    .accessibilityLabel("\(parameter.rawValue) 기본값 복원")
            }
        }
        .disabled(controller.loading || controller.capturing)
    }
}
