import SwiftUI

/// 모달이 아닌 실시간 조절 패널 안에 표시되는 조명 조절 화면입니다.
struct ARLiveLightingPanel: View {
    @Bindable var controller: ARSessionController
    @State private var parameter: Parameter = .intensity

    private enum Parameter: String, CaseIterable, Identifiable {
        case intensity = "강도", azimuth = "방위", elevation = "고도", environment = "환경"
        var id: Self { self }
    }

    private var value: Binding<Float> {
        switch parameter {
        case .intensity: $controller.settings.intensity
        case .azimuth: $controller.settings.azimuth
        case .elevation: $controller.settings.elevation
        case .environment: $controller.settings.exposure
        }
    }

    private var range: ClosedRange<Float> {
        switch parameter {
        case .intensity: 0...10000
        case .azimuth: -180...180
        case .elevation: 5...90
        case .environment: -2...2
        }
    }

    private var enabled: Bool {
        parameter == .environment ? controller.settings.environmentLight : controller.settings.directLight
    }

    private var formattedValue: String {
        switch parameter {
        case .intensity: String(format: "%.0f", value.wrappedValue)
        case .azimuth, .elevation: String(format: "%.0f°", value.wrappedValue)
        case .environment: String(format: "%+.2f EV", value.wrappedValue)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("조절 항목", selection: $parameter) {
                ForEach(Parameter.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                if parameter == .environment {
                    Toggle("환경 조명", isOn: $controller.settings.environmentLight)
                } else {
                    Toggle("보조 광원", isOn: $controller.settings.directLight)
                }
                Text(formattedValue).monospacedDigit().frame(minWidth: 88, alignment: .trailing)
            }.font(.subheadline)
            Slider(value: value, in: range)
                .disabled(!enabled || controller.capturing)
                .accessibilityLabel(parameter == .environment ? "환경 조명 밝기" : "보조 광원 \(parameter.rawValue)")
                .accessibilityValue(formattedValue)
            HStack {
                Text(enabled ? (parameter == .environment ? "주변 조명 밝기 보정" : "AR 공간 기준 · 실제 태양 방향 아님") : "광원을 켜면 조절 결과가 반영됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    controller.settings.groundingShadow.toggle()
                } label: {
                    Text(controller.settings.groundingShadow ? "그림자 켜짐" : "그림자 꺼짐")
                        .font(.caption)
                }.buttonStyle(.bordered)
                .accessibilityLabel("접지 그림자")
                .accessibilityValue(controller.settings.groundingShadow ? "켜짐" : "꺼짐")
            }
        }
    }
}
