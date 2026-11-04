import SwiftUI

struct CampusSearchChoiceSheet: View {
    let choose: (CampusSearchMode) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("검색 방식 선택").font(CampusStyle.semibold(26)).foregroundStyle(CampusStyle.sectionGreen)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 23)).frame(width: 38, height: 38) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("검색 방식 닫기")
            }
            ForEach(CampusSearchMode.allCases) { mode in
                Button { choose(mode) } label: {
                    Text(mode.choice).font(CampusStyle.medium(20)).foregroundStyle(CampusStyle.mapAction)
                        .frame(maxWidth: .infinity, minHeight: 66).background(.white, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("campus.search.mode.\(mode.rawValue)")
            }
        }.padding(20).padding(.bottom, 20)
            .presentationDetents([.height(356)]).presentationCornerRadius(35)
            .presentationDragIndicator(.hidden)
            .presentationBackground { CampusStyle.mapSheet.opacity(0.7).background(.ultraThinMaterial) }
    }
}

struct CampusSearchView: View {
    let mode: CampusSearchMode
    let entries: [CampusSearchEntry]
    let isExample: Bool
    let onSelect: (CampusSearchEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = CampusSearchQuery()
    @State private var submitted: CampusSearchQuery?
    @FocusState private var focused: Bool

    private var results: [CampusSearchEntry] {
        if mode == .donor { return submitted.map { filter($0) } ?? [] }
        // Name browsing starts with all available records; a code must be entered exactly.
        return filter(query)
    }
    private func filter(_ query: CampusSearchQuery) -> [CampusSearchEntry] { entries.filter { $0.matches(query, mode: mode) } }
    private var hasSearched: Bool {
        mode == .donor ? submitted != nil : !CampusSearchQuery.normalized(query.text).isEmpty
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if mode == .donor {
                        VStack(spacing: 10) {
                            field("학교입력", text: $query.school, icon: "pencil")
                            field("공개 닉네임", text: $query.name, icon: "pencil")
                            Text("공개된 학교와 닉네임으로 검색해요.").font(.caption).foregroundStyle(.secondary)
                            Button { submitted = query; focused = false } label: {
                                Text("검색").font(CampusStyle.semibold(18)).foregroundStyle(query.hasDonorFilter ? .white : CampusStyle.secondaryAction)
                                    .frame(maxWidth: .infinity, minHeight: 41)
                                    .background(query.hasDonorFilter ? CampusStyle.green : Color(red: 241/255, green: 244/255, blue: 236/255), in: Capsule())
                            }.buttonStyle(.plain).disabled(!query.hasDonorFilter).accessibilityIdentifier("campus.search.submit")
                        }
                    } else {
                        field(mode == .code ? "코드입력" : "검색", text: $query.text, icon: "magnifyingglass")
                            .accessibilityIdentifier("campus.search.query")
                    }
                    LazyVStack(spacing: 14) {
                        ForEach(results) { entry in
                            Button { focused = false; onSelect(entry) } label: {
                                CampusStoryRow(story: entry.story, showsDate: false, outlined: true)
                            }.buttonStyle(.plain).accessibilityIdentifier("campus.search.result.\(entry.id)")
                        }
                        if results.isEmpty && hasSearched {
                            ContentUnavailableView.search(text: mode == .donor ? "입력한 조건" : query.text)
                        } else if entries.isEmpty {
                            ContentUnavailableView("아직 공개된 오이가 없어요", systemImage: "leaf", description: Text("캠퍼스에 이야기가 올라오면 이곳에서 찾을 수 있어요."))
                        }
                    }
                    if isExample {
                        Text("기기 예시 · 실제 기부자 정보가 아닙니다.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively).background(.white)
                .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text(mode.title).font(CampusStyle.medium(20)).minimumScaleFactor(0.8) }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }.font(CampusStyle.body(20)).tint(.gray)
                    }
                }
        }.tint(CampusStyle.mapAction)
    }
    private func field(_ prompt: String, text: Binding<String>, icon: String) -> some View {
        HStack {
            TextField(prompt, text: text).font(CampusStyle.medium(18)).focused($focused)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .onSubmit { if mode == .donor && query.hasDonorFilter { submitted = query }; focused = false }
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.gray).accessibilityHidden(true)
        }.padding(.horizontal, 22).frame(minHeight: 57)
            .background(Color(white: 217/255).opacity(0.3), in: Capsule())
    }
}

private enum CampusSchool: String, CaseIterable, Identifiable {
    case postech, hanyang, chungnam, kaist
    var id: String { rawValue }
    var title: String {
        switch self {
        case .postech: "POSTECH"
        case .hanyang: "한양대학교"
        case .chungnam: "충남대학교"
        case .kaist: "KAIST"
        }
    }
    var keywords: String {
        switch self {
        case .postech: "POSTECH 포스텍 포항공과대학교"
        case .hanyang: "한양대학교 한양대 Hanyang"
        case .chungnam: "충남대학교 충남대 Chungnam CNU"
        case .kaist: "KAIST 카이스트 한국과학기술원"
        }
    }
    var logoImage: String {
        switch self {
        case .postech: "CampusSchoolLogo"
        case .hanyang: "CampusHanyangLogo"
        case .chungnam: "CampusChungnamLogo"
        case .kaist: "CampusKAISTLogo"
        }
    }
    // Match the visible school name rather than the complete artwork height:
    // POSTECH is a wide wordmark; CNU includes a tall seal and English subtitle.
    var logoHeight: CGFloat {
        switch self {
        case .postech: 18
        case .chungnam: 74
        case .hanyang, .kaist: 52
        }
    }
    var mapImage: String {
        switch self {
        case .postech: "CampusSchoolMap"
        case .hanyang: "CampusHanyangMap"
        case .chungnam: "CampusChungnamMap"
        case .kaist: "CampusKAISTMap"
        }
    }
}

struct CampusSchoolSearchView: View {
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var schools: [CampusSchool] {
        let term = CampusSearchQuery.normalized(query)
        return CampusSchool.allCases.filter { term.isEmpty || CampusSearchQuery.normalized($0.keywords).contains(term) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    HStack {
                        TextField("검색", text: $query).font(CampusStyle.semibold(18))
                            .autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.search)
                            .accessibilityIdentifier("campus.school.query")
                        Image(systemName: "magnifyingglass").foregroundStyle(.gray)
                    }.padding(.horizontal, 22).frame(height: 57)
                        .background(Color(white: 217/255).opacity(0.3), in: Capsule())
                    ForEach(schools) { school in
                        if school == .postech {
                            Button(action: onSelect) { schoolCard(school) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("POSTECH 포항공과대학교 지도 열기")
                                .accessibilityIdentifier("campus.school.postech")
                        } else {
                            NavigationLink { CampusSchoolMapPreview(school: school) } label: { schoolCard(school) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(school.title) 지도 미리보기")
                                .accessibilityIdentifier("campus.school.\(school.id)")
                        }
                    }
                    if schools.isEmpty { ContentUnavailableView.search(text: query) }
                }.padding(20)
            }.background(.white).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.tint(.gray) } }
            #if DEBUG
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "-campus-school-query"), args.indices.contains(index + 1) {
                    query = args[index + 1]
                }
            }
            #endif
        }
    }

    private func schoolCard(_ school: CampusSchool) -> some View {
        VStack(spacing: 10) {
            Image(school.logoImage).resizable().scaledToFit()
                .frame(height: school.logoHeight).padding(.horizontal, 38)
                .accessibilityLabel(school.title)
            Image(school.mapImage).resizable().scaledToFit().padding(.horizontal, 16)
                .accessibilityHidden(true)
            if school != .postech {
                Text("지도 미리보기 · 3D 탐색 준비 중").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.top, 21).padding(.bottom, 14)
            .frame(maxWidth: .infinity).background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct CampusSchoolMapPreview: View {
    let school: CampusSchool
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    private var displayZoom: CGFloat { min(max(zoom * magnification, 1), 4) }

    var body: some View {
        VStack(spacing: 16) {
            Image(school.logoImage).resizable().scaledToFit().frame(height: school.logoHeight)
                .padding(.horizontal, 38).accessibilityLabel(school.title)
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(school.mapImage).resizable().scaledToFit()
                        .frame(width: geometry.size.width * displayZoom, height: geometry.size.height * displayZoom)
                        .accessibilityLabel("\(school.title) 캠퍼스 일러스트")
                }
                .simultaneousGesture(MagnifyGesture()
                    .updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 4) })
            }
            Text("두 손가락으로 확대해 지도를 살펴보세요.").font(.caption).foregroundStyle(.secondary)
            Text("이 캠퍼스의 3D 탐색과 오이 배치는 준비 중이에요.")
                .font(.callout).multilineTextAlignment(.center)
            if school == .kaist {
                Text("캠퍼스 선택용 AI 일러스트로, 실제 길 안내와 다를 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.padding(20).background(Color(white: 0.95))
            .navigationTitle(school.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("원래 크기") { zoom = 1 } } }
    }
}
