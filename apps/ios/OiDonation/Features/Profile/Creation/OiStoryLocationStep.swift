import SwiftUI

struct OiStoryLocationStep: View {
    let choose: (String?) -> Void
    @State private var query: String
    @State private var data: CampusMapData?
    @State private var error: String?
    @FocusState private var searchFocused: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ScaledMetric(relativeTo: .body) private var emptyLineHeight: CGFloat = 27
    private let searchBackground = Color(white: 217 / 255).opacity(0.3)

    init(initialQuery: String = "", choose: @escaping (String?) -> Void) {
        _query = State(initialValue: initialQuery)
        self.choose = choose
    }

    var body: some View {
        let searchTerm = query.filter { !$0.isWhitespace }
        let places = (data?.pois ?? [])
            .filter { searchTerm.isEmpty || $0.name.filter { !$0.isWhitespace }.localizedCaseInsensitiveContains(searchTerm) }
            .sorted { a, b in
                let featured = ["72", "53", "24", "88"]
                let left = featured.firstIndex(of: a.id) ?? featured.count
                let right = featured.firstIndex(of: b.id) ?? featured.count
                return left == right ? a.name < b.name : left < right
            }

        VStack(spacing: 0) {
            searchControls.padding(.horizontal, 20).padding(.bottom, 16)
            Rectangle().fill(CampusStyle.listBackground).frame(height: 6)
                .accessibilityHidden(true)
            ScrollView {
                if let error {
                    Text(error).font(.callout).foregroundStyle(.secondary).padding(20)
                } else if data == nil {
                    ProgressView("장소 목록 불러오는 중").padding(20)
                } else if places.isEmpty {
                    noSearchResults
                }
                LazyVStack(spacing: 0) {
                    ForEach(places) { place in
                        Button { selectPlace(place.id) } label: {
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
                            .accessibilityIdentifier("oi.location.place." + place.id)
                        Rectangle().fill(Color(white: 244 / 255)).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }.padding(.horizontal, 20)
            }.scrollDismissesKeyboard(.interactively)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white)
        .task {
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

    private func selectPlace(_ id: String?) {
        searchFocused = false
        choose(id)
    }

    private var searchControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("검색", text: $query)
                    .font(CampusStyle.medium(18)).tracking(0.36)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .accessibilityLabel("건물·장소 검색")
                    .accessibilityIdentifier("oi.location.search")
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(minHeight: 57)
            .background(searchBackground, in: Capsule())
            Button { selectPlace(nil) } label: {
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
