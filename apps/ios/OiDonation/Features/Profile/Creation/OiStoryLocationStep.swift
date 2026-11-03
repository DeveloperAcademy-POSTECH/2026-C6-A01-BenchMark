import SwiftUI

struct OiStoryLocationStep: View {
    @Binding var draft: OiStoryDraft
    let regions: [OiRegion]
    let choose: (String?) -> Void
    @State private var query = ""
    @State private var data: CampusMapData?
    @State private var error: String?
    private var places: [CampusMapData.Place] {
        (data?.pois ?? []).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name < $1.name }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("POSTECH 캠퍼스에서 오이를 심을 곳을 찾아보세요.").font(.headline)
            HStack {
                TextField("건물·장소 검색", text: $query)
                Image(systemName: "magnifyingglass")
            }.padding(16).background(Color(.secondarySystemBackground), in: Capsule())
            Button { choose(nil) } label: { Label("3D 캠퍼스에서 직접 선택", systemImage: "map") }
                .buttonStyle(.borderedProminent).tint(Color("OiGreen"))
                .accessibilityIdentifier("oi.location.openMap")
            if let latitude = draft.latitude, let longitude = draft.longitude {
                Label("선택한 위치", systemImage: "mappin.circle.fill").foregroundStyle(Color("OiGreen"))
                Text(String(format: "위도 %.7f · 경도 %.7f", latitude, longitude)).font(.caption.monospacedDigit())
            } else { Text("아직 위치를 선택하지 않았어요.").foregroundStyle(.secondary) }
            if !regions.isEmpty {
                Picker("이야기를 표시할 구역", selection: $draft.regionId) {
                    ForEach(regions) { Text($0.name).tag($0.id) }
                }.tint(Color("OiGreen"))
            }
            Text("장소 검색은 지도를 이동해요. 지도에서 바닥을 누른 뒤 미세 조정하고 저장해 주세요. 현장 AR에는 GPS·방향 오차가 있을 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            LazyVStack(spacing: 0) {
                ForEach(places) { place in
                    Button { choose(place.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(place.name).font(CampusStyle.medium(16))
                                Text("포항공과대학교 · 지도에서 위치 지정").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "map").foregroundStyle(Color("OiGreen"))
                        }.padding(.vertical, 14)
                    }.buttonStyle(.plain)
                    Divider()
                }
                if places.isEmpty && data != nil { ContentUnavailableView.search(text: query) }
            }
        }.task {
            do { data = try CampusMapData.load() }
            catch { self.error = "캠퍼스 장소 목록을 불러오지 못했어요. 3D 지도에서 다시 시도해 주세요." }
        }
    }
}
