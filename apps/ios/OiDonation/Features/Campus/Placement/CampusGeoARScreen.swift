import SwiftUI
import RealityKit
import ARKit

struct CampusGeoARScreen: View {
    let placement: CampusPlacement
    let stories: CampusStoryStore
    var shared: CampusSharedStore? = nil
    @State private var livePlacement: CampusPlacement?
    @State private var sharedError: String?
    private var target: CampusPlacement { livePlacement ?? placement }
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
                    Text(shared == nil ? "현장 AR · 기기 테스트" : "공유 오이 · 현장 AR").font(.headline)
                    Spacer()
                    Button("닫기", systemImage: "xmark") { controller.stop(); dismiss() }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.mode.rawValue).font(.headline)
                    Text(sharedError ?? controller.message).font(.subheadline)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let fix = location.location {
                            if fix.horizontalAccuracy >= 0 {
                                Text("목표까지 약 \(target.distance(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude), specifier: "%.0f")m · GPS 불확실성 반경 \(fix.horizontalAccuracy, specifier: "%.0f")m")
                                Text(location.isReady(for: target) ? "근접 조건 충족 · 정확한 배치 보장 아님" : "위치 재확인 중")
                            } else { Text("유효한 GPS 위치를 기다리고 있어요.") }
                        } else { Text(location.message) }
                    }.font(.caption)
                    Text("GPS 모드는 나침반과 주변 바닥 높이로 근사 배치합니다. 경사·계단에서는 높이가 다를 수 있고, 직접 바닥 보정은 이 세션에만 적용됩니다.")
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
            sharedError = nil
            do {
                if let shared { livePlacement = try await shared.story(placement.id, publicOnly: true).placement }
                try Task.checkCancellation()
                await controller.start(target, location: location)
                // Refresh publication and coordinates while AR is visible. Hidden/deleted stories stop rendering.
                if let shared {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(30))
                        let updated = try await shared.story(placement.id, publicOnly: true)
                        if updated.placement != target {
                            livePlacement = updated.placement
                            await controller.start(updated.placement, location: location)
                        }
                    }
                }
            } catch is CancellationError { }
            catch { controller.stop(); sharedError = error.localizedDescription }
        }
        .onChange(of: scenePhase) { _, phase in
            restartID = UUID() // Cancel in-flight server reads as well as the AR session.
            if phase != .active { controller.stop() }
        }
        .onAppear { if !showingStory { restartID = UUID() } }
        .onDisappear { controller.stop() }
        .onChange(of: showingStory) { _, showing in
            restartID = UUID()
            if showing { controller.stop() }
        }
        .sheet(isPresented: $showingStory) {
            NavigationStack {
                Group {
                    if let shared {
                        CampusSharedStoryView(id: placement.id, store: shared)
                    } else if let story = stories.story(placement.storyID) {
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
