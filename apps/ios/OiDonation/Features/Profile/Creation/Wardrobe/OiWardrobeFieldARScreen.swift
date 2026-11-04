import SwiftUI

struct OiWardrobeFieldARScreen: View {
    let trial: OiWardrobeFieldTrial
    @State private var controller = CampusGeoARController()
    @State private var location = CampusGeoLocation()
    @State private var retry = UUID()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            CampusGeoSurface(controller: controller).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text("\(trial.name) · 150cm · 이 기기 테스트").font(.headline)
                Text(controller.mode.rawValue).font(.subheadline.bold())
                Text(controller.message).font(.footnote)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let fix = location.location, fix.horizontalAccuracy >= 0 {
                        Text("목표까지 \(trial.placement.distance(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude), specifier: "%.0f")m · GPS 오차 \(fix.horizontalAccuracy, specifier: "%.0f")m")
                    } else { Text(location.message) }
                }.font(.caption).monospacedDigit()
                Spacer()
                Text("목표 25m 이내·GPS 오차 15m 이하에서 표시돼요. GPS와 나침반 오차가 있으므로 실제 발 위치를 확인하세요. 직접 바닥 보정은 이번 세션에만 적용됩니다.")
                    .font(.caption)
                HStack {
                    Button("GPS 근사 배치") { controller.startApproximate() }
                    Button("직접 바닥 보정") { controller.startApproximate(manual: true) }
                }.disabled(!controller.canChangeMode)
                HStack {
                    Button("다시 확인") { retry = UUID() }
                    Button("다시 배치") { controller.reset() }.disabled(!controller.canChangeMode)
                    Button("권한 설정") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }.font(.caption)
            }.padding().foregroundStyle(.white)
                .background(LinearGradient(colors: [.black.opacity(0.75), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
                .buttonStyle(.bordered)
        }
        .navigationTitle("현장 AR 테스트").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: retry) {
            guard phase == .active else { return }
            await controller.start(trial.placement, location: location, wardrobe: trial.look)
        }
        .onChange(of: phase) { _, value in
            controller.stop()
            if value == .active { retry = UUID() }
        }
        .onDisappear { controller.stop() }
    }
}
