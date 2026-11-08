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

struct OiDraftPlacementPreview: View {
    let draft: OiStoryDraft
    let wardrobe: OiWardrobeLook?
    let onEdit: () -> Void
    let onEditLocation: () -> Void
    let onReview: () -> Void
    let onPlacementChange: (CampusPlacement, CampusRegion?) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = CampusExploreScene()
    @State private var retry = 0
    @State private var locationError: String?

    private var placement: CampusPlacement? {
        guard let latitude = draft.latitude, let longitude = draft.longitude else { return nil }
        return CampusPlacement.story(id: draft.id, latitude: latitude, longitude: longitude,
            heightMeters: draft.heightMeters, headingDegrees: draft.headingDegrees ?? 180)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("오이 배치 미리보기")
                .font(CampusStyle.semibold(20))
                .foregroundStyle(Color("OiDark"))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 54)
                .overlay(alignment: .leading) {
                    Button {
                        scene.commitPlacementPreview()
                        onEdit()
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 52, height: 48)
                    }
                    .foregroundStyle(Color("OiDark"))
                    .accessibilityLabel("카드 꾸미기로 돌아가기")
                }
            if let placement {
                CampusMapSurface(scene: scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("선택한 위치의 3D 캠퍼스 지도")
                    .accessibilityHint("한 손가락으로 오이를 이동하고, 두 손가락으로 높이와 방향을 조절해요.")
                    .overlay {
                        if let locationError {
                            locationPrompt(locationError)
                        } else if let error = scene.error ?? scene.placementError {
                            ContentUnavailableView {
                                Label("배치 미리보기를 불러올 수 없어요", systemImage: "map")
                            } description: {
                                Text(error)
                            } actions: {
                                Button("다시 시도") { retry += 1 }
                            }.background(.regularMaterial)
                        } else if !scene.placementReady {
                            ProgressView("지도와 내 오이를 불러오는 중")
                                .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let error = scene.previewMovementError {
                            Text(error).font(CampusStyle.body(13)).multilineTextAlignment(.center)
                                .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(8).allowsHitTesting(false)
                        }
                    }
                    .task(id: retry) { await prepare(placement) }
                    .onChange(of: scenePhase, initial: true) { _, phase in
                        scene.setVisible(phase == .active)
                    }
                    .onDisappear { scene.suspendForARCamera() }
            } else {
                locationPrompt("내 오이를 놓을 캠퍼스 위치를 선택해 주세요.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 8) {
                Text("포항공과대학교 · \(draft.cucumberName.isEmpty ? "내 오이" : draft.cucumberName)")
                    .font(CampusStyle.semibold(16))
                    .foregroundStyle(Color("OiDark"))
                if let placement = scene.placementPreview {
                    Label("현장 AR 높이 \(placement.heightCentimeters)cm", systemImage: "ruler")
                        .font(CampusStyle.semibold(17))
                        .accessibilityIdentifier("oi.creation.placementHeight")
                    Text("한 손가락으로 이동 · 핀치로 높이 조절\n두 손가락을 좌우로 움직이거나 비틀어 회전")
                        .font(CampusStyle.body(13)).foregroundStyle(.secondary)
                    Text("사진 속 크기는 촬영 거리와 각도에 따라 달라져요.")
                        .font(CampusStyle.body(12)).foregroundStyle(.secondary)
                }
                OiCreationNextButton(title: "검토 요청 계속하기") {
                    scene.commitPlacementPreview()
                    onReview()
                }
                    .accessibilityIdentifier("oi.creation.reviewPlacement")
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private func locationPrompt(_ message: String) -> some View {
        ContentUnavailableView {
            Label("오이 위치를 확인해 주세요", systemImage: "mappin.circle")
        } description: {
            Text(message)
        } actions: {
            Button("위치 다시 선택", action: onEditLocation)
        }.background(.regularMaterial)
    }

    private func prepare(_ placement: CampusPlacement) async {
        scene.setSharedMap(true)
        await scene.load()
        guard !Task.isCancelled, let data = scene.data else { return }
        let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
        if let error = data.placementError(at: point) {
            locationError = error
            return
        }
        scene.onPreviewChange = onPlacementChange
        scene.beginPlacementPreview(placement)
        await scene.preparePlacements(wardrobe: wardrobe)
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
