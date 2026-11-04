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
    let remote: OiRemoteStore?
    let onSelect: (CampusSearchEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: CampusSearchQuery
    @State private var submitted: CampusSearchQuery?
    @FocusState private var focused: Bool

    init(mode: CampusSearchMode, entries: [CampusSearchEntry], isExample: Bool, remote: OiRemoteStore? = nil,
         initialQuery: CampusSearchQuery = CampusSearchQuery(), onSelect: @escaping (CampusSearchEntry) -> Void) {
        self.mode = mode
        self.entries = entries
        self.isExample = isExample
        self.remote = remote
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
        _submitted = State(initialValue: mode == .donor && initialQuery.hasDonorFilter ? initialQuery : nil)
    }

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
        let matches = results
        let showsNoMatches = remote?.hasLoadedRemote != false && remote?.loadError == nil && hasSearched && matches.isEmpty

        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 28) {
                        searchFields
                        if showsNoMatches {
                            CampusSearchEmptyResult(mode: mode)
                                .frame(maxHeight: .infinity)
                        } else {
                            searchResults(matches)
                        }
                        if isExample {
                            Text("기기 예시 · 실제 기부자 정보가 아닙니다.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    // The reference reserves 64pt above the bottom safe area below the empty result.
                    .padding(.bottom, showsNoMatches ? 64 : 24)
                    .frame(minHeight: showsNoMatches ? viewport.size.height : nil)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(.white)
            .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(mode.title).font(CampusStyle.medium(20)).minimumScaleFactor(0.8) }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.font(CampusStyle.body(20)).tint(.gray)
                }
            }
        }.tint(CampusStyle.mapAction)
    }

    @ViewBuilder private var searchFields: some View {
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
    }

    private func searchResults(_ matches: [CampusSearchEntry]) -> some View {
        LazyVStack(spacing: 14) {
            if let remote, !remote.hasLoadedRemote || (hasSearched && matches.isEmpty && remote.loadError != nil) {
                if remote.isRefreshing || remote.isBusy || remote.loadError == nil {
                    ProgressView().accessibilityLabel("이야기 불러오는 중")
                } else {
                    OiConnectionStatus(remote: remote, showsInitialProgress: false)
                }
            } else {
                ForEach(matches) { entry in
                    Button { focused = false; onSelect(entry) } label: {
                        CampusStoryRow(story: entry.story, showsDate: false, outlined: true)
                    }.buttonStyle(.plain).accessibilityIdentifier("campus.search.result.\(entry.id)")
                }
                if entries.isEmpty {
                    ContentUnavailableView("아직 공개된 오이가 없어요", systemImage: "leaf", description: Text("캠퍼스에 이야기가 올라오면 이곳에서 찾을 수 있어요."))
                }
            }
        }
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

private struct CampusSearchEmptyResult: View {
    let mode: CampusSearchMode
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var lineHeight = 27.0

    var body: some View {
        Group {
            if mode == .donor {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        illustration(width: 97, height: 151)
                        message.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        illustration(width: 97, height: 151)
                        message
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 16) {
                    illustration(width: 192, height: 300)
                    message.multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("campus.search.noMatches")
    }

    private var message: some View {
        let copy = switch mode {
        case .name: "해당 이름을 가진 오이가 없습니다\n오이이름이 정확한지 한번 더 확인해주세요"
        case .code: "해당 코드를 가진 오이가 없습니다\n오이코드가 정확한지 한번 더 확인해주세요"
        case .donor: "해당 정보를 가진 유저가 없습니다\n유저 정보가 정확한지\n한번 더 확인해주세요"
        }
        return Text(copy)
            .font(CampusStyle.medium(18))
            .tracking(0.36)
            .lineHeight(.exact(points: lineHeight))
            .foregroundStyle(contrast == .increased ? CampusStyle.sectionGreen : Color("OiGreen"))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func illustration(width: CGFloat, height: CGFloat) -> some View {
        Image("CampusSearchNoResults").resizable().scaledToFit()
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

struct CampusSchoolSearchView: View {
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
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
                    let term = CampusSearchQuery.normalized(query)
                    if term.isEmpty || CampusSearchQuery.normalized("POSTECH 포스텍 포항공과대학교").contains(term) {
                        Button(action: onSelect) { schoolCard }
                            .buttonStyle(.plain)
                            .accessibilityLabel("POSTECH 포항공과대학교 지도 열기")
                            .accessibilityIdentifier("campus.school.postech")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }.padding(20)
            }.background(.white).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.tint(.gray) } }
        }
    }

    private var schoolCard: some View {
        VStack(spacing: 10) {
            Image("CampusSchoolLogo").resizable().scaledToFit()
                .frame(height: 18).padding(.horizontal, 38)
                .accessibilityHidden(true)
            Image("CampusSchoolMap").resizable().scaledToFit().padding(.horizontal, 16)
                .accessibilityHidden(true)
        }.padding(.top, 21).padding(.bottom, 14)
            .frame(maxWidth: .infinity).background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 20))
    }
}
