import SwiftUI

/// Keep the destination and its search focus in the same presentation state.
struct OiLocationPickerRequest: Identifiable {
    let id = UUID()
    let focusPlaceID: String?
}

struct OiLocationPicker: View {
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    var focusPlaceID: String? = nil
    @State private var scene = CampusExploreScene()
    @State private var isOnScreen = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            CampusMapSurface(scene: scene)
                .ignoresSafeArea(.container, edges: .top)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error = scene.error ?? scene.placementError {
                            Text(error).foregroundStyle(.red)
                            Button("다시 시도") { Task { await prepare() } }
                        } else if scene.isLoading || scene.placementLoading {
                            ProgressView("캠퍼스 지도 준비 중")
                        }
                        Text(scene.placementMessage).font(.footnote)
                        CampusPlacementTools(scene: scene)
                    }.padding().background(.regularMaterial)
                }
                .navigationTitle("오이 위치 지정").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("이 위치로 지정") {
                            guard let point = scene.draftPoint, let data = scene.data,
                                  data.placementError(at: point) == nil else { return }
                            let coordinate = data.coordinate(point)
                            latitude = coordinate.latitude; longitude = coordinate.longitude
                            dismiss()
                        }.disabled(scene.draftPoint == nil || !scene.placementReady)
                    }
                }
        }
        .task { await prepare() }
        .onAppear { isOnScreen = true; scene.setVisible(scenePhase == .active) }
        .onDisappear { isOnScreen = false; scene.endPlacement(); scene.suspendForARCamera() }
        .onChange(of: scenePhase) { _, phase in scene.setVisible(isOnScreen && phase == .active) }
    }

    private func prepare() async {
        await scene.load()
        guard !Task.isCancelled else { return }
        await scene.preparePlacements()
        guard !Task.isCancelled, scene.placementReady else { return }
        let existing: CampusPlacement?
        if let latitude, let longitude {
            existing = CampusPlacement(storyID: "draft-location", latitude: latitude, longitude: longitude)
        } else { existing = nil }
        scene.beginPlacement(editing: existing)
        if let focusPlaceID { scene.focusPlaceForPlacement(focusPlaceID) }
    }
}
