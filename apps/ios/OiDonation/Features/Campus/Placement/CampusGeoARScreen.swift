import SwiftUI
import RealityKit
import ARKit

struct CampusGeoARScreen: View {
    let placement: CampusPlacement
    let stories: CampusStoryStore
    @State private var controller = CampusGeoARController()
    @State private var location = CampusGeoLocation()
    @State private var showingStory = false
    @State private var restartID = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            CampusGeoSurface(controller: controller).ignoresSafeArea()
            VStack {
                HStack {
                    Text("현장 AR · 기기 테스트").font(.headline)
                    Spacer()
                    Button("닫기", systemImage: "xmark") { controller.stop(); dismiss() }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.mode.rawValue).font(.headline)
                    Text(controller.message).font(.subheadline)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let fix = location.location {
                            Text("목표까지 \(placement.distance(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude), specifier: "%.0f")m · GPS ±\(fix.horizontalAccuracy, specifier: "%.0f")m · \(location.isReady(for: placement) ? "위치 확인됨" : "위치 재확인 중")")
                        } else { Text(location.message) }
                    }.font(.caption)
                    Text("GPS 배치는 근사 위치이며, 직접 바닥 보정은 이 세션에만 적용됩니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                VStack(spacing: 10) {
                    HStack {
                        Button("GPS 근사 배치") { controller.startApproximate() }
                        Button("직접 바닥 보정") { controller.startApproximate(manual: true) }
                    }.disabled(!controller.canChangeMode)
                    HStack {
                        Button("다시 확인") { restartID = UUID() }
                        Button("다시 배치") { controller.reset() }.disabled(!controller.canChangeMode)
                        Button("권한 설정") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }.font(.caption)
                }.buttonStyle(.bordered)
            }
            .padding(16)
            .background(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            }
            .foregroundStyle(.white)
        }
        .task(id: restartID) {
            guard scenePhase == .active, !showingStory else { return }
            controller.onStory = { showingStory = true }
            await controller.start(placement, location: location)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { restartID = UUID() } else { controller.stop() }
        }
        .onAppear { if !showingStory { restartID = UUID() } }
        .onDisappear { controller.stop() }
        .onChange(of: showingStory) { _, showing in
            if showing { controller.stop() } else { restartID = UUID() }
        }
        .sheet(isPresented: $showingStory) {
            NavigationStack {
                Group {
                    if let story = stories.story(placement.storyID) {
                        CampusStoryDetailView(story: story, store: stories)
                            .navigationDestination(for: CampusDestination.self) { destination in
                                // Keep related stories in this sheet without starting a second 3D renderer over AR.
                                switch destination {
                                case .summary(let id), .story(let id):
                                    if let related = stories.story(id) { CampusStoryDetailView(story: related, store: stories) }
                                }
                            }
                    }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("AR로 돌아가기") { showingStory = false } } }
            }
        }
    }
}

private struct CampusGeoSurface: UIViewRepresentable {
    let controller: CampusGeoARController
    func makeUIView(context: Context) -> RealityKit.ARView { controller.makeView() }
    func updateUIView(_ view: RealityKit.ARView, context: Context) { }
    static func dismantleUIView(_ view: RealityKit.ARView, coordinator: ()) {
        view.session.pause()
        view.session.delegate = nil
        view.scene.anchors.removeAll()
    }
}
