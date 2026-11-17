import SwiftUI
import ARKit

struct ARPhotoSettingsPanel: View {
    @Binding var settings: ARCaptureSettings
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("사진 설정").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "chevron.down").frame(width: 44, height: 32) }
                    .accessibilityLabel("사진 설정 패널 접기")
            }
            HStack {
                Label("타이머", systemImage: "timer")
                Spacer()
                Picker("타이머", selection: $settings.photoTimer) {
                    Text("끔").tag(0)
                    Text("3초").tag(3)
                    Text("10초").tag(10)
                }.pickerStyle(.segmented).frame(maxWidth: 210)
            }
            Picker("사진 비율", selection: $settings.photoRatio) {
                ForEach(ARPhotoRatio.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            VStack(spacing: 8) {
                HStack {
                    Label("노출", systemImage: "plusminus.circle")
                    Spacer()
                    Text(String(format: "%+.1f EV", settings.cameraExposure)).monospacedDigit()
                    Button("초기화") { settings.cameraExposure = 0 }.font(.caption)
                }
                Slider(value: $settings.cameraExposure, in: -2...2, step: 0.1)
                    .accessibilityLabel("카메라 노출")
                    .disabled(ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera == nil)
            }
            Toggle("촬영 영역 밖 배경을 검정색으로", isOn: $settings.opaquePhotoMargins)
                .font(.subheadline)
            Picker("필터", selection: $settings.photoFilter) {
                ForEach(ARPhotoFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
    }
}
