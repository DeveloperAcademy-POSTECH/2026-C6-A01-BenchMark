//
//  BenchesView.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/16/26.
//

import CoreLocation
import MapKit
import UIKit
import SwiftUI

struct BenchesView: View {
    let repository: any BenchRepository
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var locationService = BenchLocationService()
    @State private var position: MapCameraPosition = .region(Self.campusRegion)
    @State private var mapAppearance = Appearance.standard
    @State private var benches: [Bench] = []
    @State private var errorMessage: String?

    // Campus overview only; this is not an approved bench or NFC coordinate.
    private static let campusRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.0139, longitude: 129.3232),
        latitudinalMeters: 2_000, longitudinalMeters: 2_000
    )

    private enum Appearance: String, CaseIterable, Identifiable {
        case standard = "일반", hybrid = "위성"
        var id: Self { self }
        var style: MapStyle {
            switch self {
            case .standard: .standard(elevation: .realistic)
            case .hybrid: .hybrid(elevation: .realistic)
            }
        }
    }

    var body: some View {
        Map(position: $position, interactionModes: .all) {
            if locationService.isAuthorized { UserAnnotation() }
            ForEach(locatedBenches) { bench in
                if let coordinate = bench.coordinate {
                    Annotation(bench.name, coordinate: coordinate.mapCoordinate) {
                        NavigationLink(value: PublicLinkParser.Destination.bench(bench.id)) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.title)
                                .padding(8)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("\(bench.name), NFC 이야기 보기")
                    }
                }
            }
        }
        .mapStyle(mapAppearance.style)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let errorMessage {
                HStack {
                    Text(errorMessage).font(.subheadline)
                    Spacer()
                    Button("재시도") { Task { await load() } }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .navigationTitle("벤치지도")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("지도 유형", selection: $mapAppearance) {
                        ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button("POSTECH 캠퍼스", systemImage: "building.2") {
                        withAnimation { position = .region(Self.campusRegion) }
                    }
                    if !locatedBenches.isEmpty {
                        Button("모든 NFC 위치", systemImage: "arrow.up.left.and.arrow.down.right") {
                            withAnimation { showAllLocations() }
                        }
                    }
                } label: { Label("지도 옵션", systemImage: "map") }
                Button {
                    locationService.locate()
                } label: {
                    if locationService.isLocating { ProgressView() }
                    else { Image(systemName: "location.fill") }
                }
                .disabled(locationService.isLocating)
                .accessibilityLabel(locationService.isLocating ? "현재 위치 찾는 중" : "내 위치로 이동")
            }
        }
        .task { await load() }
        .onChange(of: locationService.focusRequest) {
            withAnimation { position = .userLocation(followsHeading: false, fallback: .region(Self.campusRegion)) }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { locationService.refreshAuthorization() }
            else if scenePhase == .background { locationService.cancel() }
        }
        .onDisappear { locationService.cancel() }
        .alert(item: $locationService.notice) { notice in
            if notice.offersSettings {
                Alert(title: Text("위치 접근 안내"), message: Text(notice.message),
                      primaryButton: .default(Text("설정 열기")) {
                          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                      }, secondaryButton: .cancel(Text("닫기")))
            } else {
                Alert(title: Text("위치 안내"), message: Text(notice.message), dismissButton: .default(Text("확인")))
            }
        }
    }

    private var locatedBenches: [Bench] { benches.filter { $0.coordinate != nil } }

    private func showAllLocations() {
        let rect = locatedBenches.compactMap(\.coordinate).reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate.mapCoordinate)
            let padding = MKMapPointsPerMeterAtLatitude(coordinate.latitude) * 300
            return rect.union(MKMapRect(x: point.x - padding, y: point.y - padding,
                                       width: padding * 2, height: padding * 2))
        }
        if !rect.isNull { position = .rect(rect) }
    }

    private func load() async {
        errorMessage = nil
        do { benches = try await repository.fetchBenches() }
        catch is CancellationError { }
        catch { errorMessage = "NFC 위치를 불러오지 못했어요." }
    }
}

#Preview("벤치지도") {
    NavigationStack { BenchesView(repository: UnconnectedPilotRepository()) }
}

struct PublicDestinationView: View {
    let destination: PublicLinkParser.Destination
    let benches: any BenchRepository
    let stories: any StoryRepository
    @State private var title = ""
    @State private var text = ""
    @State private var isLoading = true
    var body: some View {
        ScrollView {
            if isLoading { ProgressView() }
            else { VStack(alignment: .leading, spacing: 16) { Text(title).font(.title2); Text(text) }.padding(24) }
        }
        .navigationTitle("이야기 벤치").task(id: destination) {
            isLoading = true
            defer { isLoading = false }
            do {
                switch destination {
                case .bench(let id):
                    if let bench = try await benches.fetchBenches().first(where: { $0.id == id }) {
                        title = bench.name; text = bench.locationDescription
                    } else { title = "벤치를 확인할 수 없어요"; text = "공개된 벤치인지 확인해 주세요." }
                case .story(let id):
                    if let story = try await stories.fetchPublicStory(plaqueID: id) {
                        title = story.title; text = story.content
                    } else { title = "이야기를 확인할 수 없어요"; text = "삭제되었거나 아직 공개되지 않은 이야기입니다." }
                }
            } catch { title = "불러오지 못했어요"; text = "잠시 후 다시 시도해 주세요." }
        }
    }
}

private extension BenchCoordinate {
    var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
