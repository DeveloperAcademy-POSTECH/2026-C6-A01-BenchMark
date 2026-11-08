import SwiftUI

struct OiLocationPicker: View {
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    var regionID: Binding<String>? = nil
    var focusPlaceID: String? = nil
    var onFinish: (() -> Void)? = nil
    @State private var scene = CampusExploreScene()
    @State private var showingMap = false
    @State private var selectedPlaceID: String?
    @State private var isOnScreen = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                searchHeader
                OiStoryLocationStep(choose: openMap)
            }
            .background(.white)
            .opacity(showingMap ? 0 : 1)
            .allowsHitTesting(!showingMap)
            .accessibilityHidden(showingMap)
            if showingMap { mapContent }
        }
        .onAppear {
            isOnScreen = true
            if let focusPlaceID, !showingMap { openMap(focusPlaceID) }
        }
        .onDisappear {
            isOnScreen = false
            scene.endPlacement()
            scene.suspendForARCamera()
        }
        .onChange(of: scenePhase) { _, phase in
            scene.setVisible(isOnScreen && showingMap && phase == .active)
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("위치 선택").font(CampusStyle.medium(20))
            }
            HStack {
                Button("취소", action: close)
                    .font(.custom("Paperlogy-3Light", size: 20, relativeTo: .body))
                    .accessibilityIdentifier("oi.location.cancel3D")
                Spacer(minLength: 8)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("위치 선택").font(CampusStyle.medium(20)).foregroundStyle(.black)
                    Spacer(minLength: 8)
                }
                Button("완료", action: close)
                    .font(CampusStyle.medium(20))
                    .disabled(latitude == nil || longitude == nil)
                    .accessibilityHint("기존에 지정한 위치를 유지해요")
            }.foregroundStyle(Color(white: 108 / 255))
        }
        .frame(minHeight: 44).padding(.horizontal, 20).padding(.top, 8)
    }

    private var mapContent: some View {
        GeometryReader { safe in
            GeometryReader { viewport in
                ZStack {
                    CampusMapSurface(scene: scene)
                    OiLocationPinShape()
                        .fill(scene.draftPoint == nil ? Color.gray : Color("OiGreen"))
                        .overlay(alignment: .top) {
                            Circle().fill(.white).frame(width: 12, height: 12).padding(.top, 12)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .frame(width: 36, height: 48)
                        .position(x: viewport.size.width / 2, y: viewport.size.height / 2 - 24)
                        .allowsHitTesting(false)
                        .accessibilityLabel("화면 중앙 위치 핀")
                        .accessibilityIdentifier("oi.location.centerPin")
                    VStack(spacing: 12) {
                        HStack {
                            Button(action: backToSearch) {
                                Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(.black).frame(width: 50, height: 50)
                                    .background(.regularMaterial, in: Circle())
                            }
                            .accessibilityLabel("장소 검색으로 돌아가기")
                            .accessibilityIdentifier("oi.location.backToSearch")
                            Spacer()
                            Text("지도를 움직여 위치를 맞춰 주세요")
                                .font(CampusStyle.body(12)).padding(10)
                                .background(.regularMaterial, in: Capsule())
                        }.padding(.top, safe.safeAreaInsets.top + 8)
                        Spacer(minLength: 8)
                        locationCard
                        Button(action: confirmLocation) {
                            Text("오이 위치로 지정하기").font(CampusStyle.medium(17))
                                .foregroundStyle(Color("OiLight"))
                                .frame(maxWidth: .infinity, minHeight: 57)
                                .background(scene.draftPoint == nil ? Color.gray : Color("OiGreen"),
                                    in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                            .disabled(!scene.ready || scene.draftPoint == nil)
                            .accessibilityIdentifier("oi.location.confirm3D")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, safe.safeAreaInsets.bottom + 15)
                }
                .task(id: selectedPlaceID) { await prepare() }
                .onAppear {
                    scene.setMapLabelPresentation(enabled: true,
                        topInset: safe.safeAreaInsets.top + 72, bottomInset: safe.safeAreaInsets.bottom + 190,
                        controls: [CGRect(x: viewport.size.width / 2 - 24,
                                          y: viewport.size.height / 2 - 48, width: 48, height: 52)])
                }
            }.ignoresSafeArea()
        }
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = scene.error {
                Text(error).font(CampusStyle.body(16))
                Button("다시 시도") { Task { await prepare() } }
            } else if !scene.ready {
                ProgressView("캠퍼스 지도 준비 중")
            } else {
                Text(scene.centerLocationName).font(CampusStyle.medium(20))
                Text(scene.centerLocationError ?? "포항공과대학교 · 핀 아래 위치로 지정")
                    .font(.custom("Paperlogy-3Light", size: 16, relativeTo: .body))
                    .foregroundStyle(scene.centerLocationError == nil ? Color.primary : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color("OiGreen"), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("oi.location.selectedPlace")
    }

    private func openMap(_ placeID: String?) {
        selectedPlaceID = placeID
        showingMap = true
        scene.setVisible(scenePhase == .active)
    }

    private func backToSearch() {
        showingMap = false
        scene.suspendForARCamera()
    }

    private func confirmLocation() {
        guard let coordinate = scene.confirmCenterLocation() else { return }
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        if let region = coordinate.region { regionID?.wrappedValue = region.id }
        close()
    }

    private func close() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    private func prepare() async {
        // A quick search → map return can overlap the previous task's cancellation.
        while scene.isLoading {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
        }
        guard !Task.isCancelled, showingMap else { return }
        await scene.load()
        guard !Task.isCancelled, showingMap, scene.ready else { return }
        scene.beginCenterLocation(latitude: latitude, longitude: longitude)
        if let selectedPlaceID { scene.focusPlaceForPlacement(selectedPlaceID) }
    }
}

/// The bottom vertex sits exactly on the camera's center ray.
private struct OiLocationPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.35, y: rect.height * 0.78),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.62))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.38),
            control1: CGPoint(x: rect.minX, y: -rect.height * 0.13),
            control2: CGPoint(x: rect.maxX, y: -rect.height * 0.13))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.62),
            control2: CGPoint(x: rect.width * 0.65, y: rect.height * 0.78))
        path.closeSubpath()
        return path
    }
}
