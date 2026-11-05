import SwiftUI

struct OiStoryLocationStep: View {
    @Binding var draft: OiStoryDraft
    let regions: [OiRegion]
    let choose: (String?) -> Void
    @State private var query: String
    @State private var data: CampusMapData?
    @State private var error: String?
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ScaledMetric(relativeTo: .body) private var emptyLineHeight: CGFloat = 27
    private let searchBackground = Color(white: 217 / 255).opacity(0.3)

    init(draft: Binding<OiStoryDraft>, regions: [OiRegion], initialQuery: String = "", choose: @escaping (String?) -> Void) {
        _draft = draft
        self.regions = regions
        _query = State(initialValue: initialQuery)
        self.choose = choose
    }

    var body: some View {
        let searchTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let places = (data?.pois ?? [])
            .filter { searchTerm.isEmpty || $0.name.localizedCaseInsensitiveContains(searchTerm) }
            .sorted { $0.name < $1.name }

        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 16) {
                searchControls
                if data != nil && error == nil && !searchTerm.isEmpty && places.isEmpty {
                    noSearchResults
                }
            }
            if let latitude = draft.latitude, let longitude = draft.longitude {
                Label("선택한 위치", systemImage: "mappin.circle.fill").foregroundStyle(Color("OiGreen"))
                Text(String(format: "위도 %.7f · 경도 %.7f", latitude, longitude)).font(.caption.monospacedDigit())
            } else { Text("아직 위치를 선택하지 않았어요.").foregroundStyle(.secondary) }
            Button { choose(nil) } label: {
                Label(draft.latitude == nil ? "포스텍 3D 지도에서 위치 선택" : "3D 지도에서 위치 수정", systemImage: "map")
                    .font(CampusStyle.semibold(16)).frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).tint(Color("OiGreen"))
                .buttonBorderShape(.roundedRectangle(radius: 20))
                .accessibilityIdentifier("oi.location.choose3D")
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
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(place.name).font(CampusStyle.medium(16)).tracking(0.32)
                                    .foregroundStyle(.black)
                                Text("포항공과대학교 · 지도에서 위치 지정")
                                    .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
                                    .tracking(0.24).foregroundStyle(Color(white: 121 / 255))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "map")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(white: 121 / 255))
                                .frame(width: 45, height: 45)
                                .background(Color(white: 234 / 255), in: Circle())
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityHint("3D 지도에서 이 장소를 열어요")
                    Rectangle().fill(Color(white: 244 / 255)).frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }.task {
            do {
                data = try CampusMapData.load()
                error = nil
            } catch {
                self.error = "캠퍼스 장소 목록을 불러오지 못했어요. 3D 지도에서 다시 시도해 주세요."
            }
        }
    }

    private var noSearchResults: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CampusStyle.listBackground)
                .frame(height: 6)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("해당 장소가 존재하지 않습니다")
                    .frame(minHeight: emptyLineHeight)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "map")
                        .accessibilityHidden(true)
                    Text("지도에서 직접 위치를 조정해보세요")
                }
                .frame(minHeight: emptyLineHeight)
            }
            .font(CampusStyle.medium(18))
            .tracking(0.36)
            .foregroundStyle(colorSchemeContrast == .increased ? Color.secondary : Color(white: 202 / 255))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 133)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("oi.location.noSearchResults")
        }
    }

    private var searchControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("검색", text: $query)
                    .font(CampusStyle.medium(18)).tracking(0.36)
                    .submitLabel(.search)
                    .accessibilityLabel("건물·장소 검색")
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(minHeight: 57)
            .background(searchBackground, in: Capsule())
            Button { choose(nil) } label: {
                Image(systemName: "map")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 57, height: 57)
                    .background(searchBackground, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("3D 캠퍼스에서 직접 선택")
            .accessibilityIdentifier("oi.location.openMap")
        }
    }
}
