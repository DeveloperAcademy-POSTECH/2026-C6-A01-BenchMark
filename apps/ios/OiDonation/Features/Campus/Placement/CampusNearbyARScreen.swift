import SwiftUI
import RealityKit
import ARKit

/// Default camera entry: no placement needs to be selected before opening AR.
struct CampusNearbyARScreen: View {
    let stories: CampusStoryStore
    let remote: OiRemoteStore
    let onPhotoCamera: () -> Void
    @State private var controller = CampusNearbyARController()
    @State private var location = CampusGeoLocation()
    @State private var publicItems: [CampusNearbyOi] = []
    @State private var sharedNotice: String?
    @State private var selected: CampusNearbyOi?
    @State private var restartID = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            CampusNearbySurface(controller: controller).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    Label("주변 오이 찾기", systemImage: "location.magnifyingglass").font(.headline)
                    Spacer()
                    Button { controller.stop(); dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("AR 카메라 닫기")
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(controller.message).font(.subheadline)
                    Text("주변 오이 \(controller.visibleCount)개 · 이동하면 자동으로 갱신돼요")
                        .font(.caption)
                    if let distance = controller.nearestDistance {
                        Text("가장 가까운 오이 약 \(distance, specifier: "%.0f")m").font(.caption)
                    }
                    if let fix = location.location, fix.horizontalAccuracy >= 0 {
                        Text("GPS 불확실성 반경 \(fix.horizontalAccuracy, specifier: "%.0f")m").font(.caption)
                    }
                    if let sharedNotice { Text(sharedNotice).font(.caption) }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    Text("GPS·나침반을 이용한 근사 위치예요. 실제 위치와 차이가 날 수 있으며, 주변 바닥을 비춰야 오이가 나타나요.")
                        .font(.caption).multilineTextAlignment(.center)
                    HStack {
                        Button("다시 확인", systemImage: "arrow.clockwise") { restartID = UUID() }
                            .accessibilityIdentifier("campus.nearby.retry")
                        Button("권한 설정", systemImage: "gearshape") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }.font(.subheadline).buttonStyle(.bordered)
                    Button("캐릭터 촬영 모드", systemImage: "camera.fill") {
                        controller.stop()
                        onPhotoCamera()
                    }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("campus.nearby.photo")
                }.padding(14).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(.black).foregroundStyle(.white).tint(.mint)
        .statusBarHidden(true)
        .task(id: restartID) { await run() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.stop() }
            restartID = UUID()
        }
        .onChange(of: selected) { _, item in
            if item != nil { controller.stop() }
            restartID = UUID()
        }
        .onDisappear { controller.stop() }
        .sheet(item: $selected) { item in
            NavigationStack {
                CampusNearbyStoryView(id: item.placement.id, stories: stories, remote: remote)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("AR로 돌아가기") { selected = nil } } }
            }
        }
    }

    private func run() async {
        guard scenePhase == .active, selected == nil else { return }
        publicItems = []
        sharedNotice = "공개된 오이를 확인하고 있어요."
        controller.setItems([])
        await controller.start(location: location)
        guard !Task.isCancelled else { return }
        controller.onStory = { selected = $0 }
        // Network refresh is independent of GPS updates. A failed read removes stale anchors.
        while !Task.isCancelled {
            do {
                let records = try await remote.publishedStories()
                try Task.checkCancellation()
                publicItems = records.compactMap { story in
                    guard let placement = try? CampusPlacement(id: story.id, storyID: story.id.uuidString,
                        latitude: story.latitude, longitude: story.longitude).validated() else { return nil }
                    return CampusNearbyOi(placement: placement, source: .shared)
                }
                sharedNotice = "공개 오이 \(publicItems.count)개 · 30초마다 갱신 · 공통 AR 모델로 표시"
                controller.setItems(publicItems)
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                publicItems = []; controller.setItems([])
                sharedNotice = "공개 오이 갱신 실패: " + error.localizedDescription
            }
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }
}

/// Re-check visibility when tapped and while reading, rather than displaying a cached withdrawn story.
private struct CampusNearbyStoryView: View {
    let id: UUID
    let stories: CampusStoryStore
    let remote: OiRemoteStore
    @State private var story: CampusStory?
    @State private var error: String?
    var body: some View {
        Group {
            if let story { CampusStoryDetailView(story: story, store: stories) }
            else if let error { ContentUnavailableView("이야기를 확인할 수 없어요", systemImage: "leaf", description: Text(error)) }
            else { ProgressView().accessibilityLabel("이야기 확인 중") }
        }
        .navigationDestination(for: CampusDestination.self) { destination in
            switch destination {
            case .summary(let value), .story(let value):
                if let nextID = UUID(uuidString: value) { CampusNearbyStoryView(id: nextID, stories: stories, remote: remote) }
            }
        }
        .task(id: id) {
            while !Task.isCancelled {
                do {
                    let item = try await remote.publishedStory(id)
                    try Task.checkCancellation()
                    story = remote.campusStory(item); error = nil
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled else { return }
                    story = nil; self.error = error.localizedDescription
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
}

private struct CampusNearbySurface: UIViewRepresentable {
    let controller: CampusNearbyARController
    func makeUIView(context: Context) -> RealityKit.ARView { controller.makeView() }
    func updateUIView(_ view: RealityKit.ARView, context: Context) { }
    static func dismantleUIView(_ view: RealityKit.ARView, coordinator: ()) {
        view.session.pause()
        view.session.delegate = nil
        view.scene.anchors.removeAll()
    }
}
