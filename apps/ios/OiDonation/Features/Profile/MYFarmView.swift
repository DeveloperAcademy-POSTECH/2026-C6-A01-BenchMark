// Created by 이돈혁

import SwiftUI

struct MYFarmView: View {
    var remote: OiRemoteStore? = nil
    var nickname = "농부"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let farmGround = Color(red: 193 / 255, green: 215 / 255, blue: 72 / 255)

    var body: some View {
        if let remote {
            let isEmptyFarm = remote.hasLoadedRemote && remote.account != nil && remote.ownStories.isEmpty
            let hasPlots = remote.hasLoadedRemote && remote.account != nil && !remote.ownStories.isEmpty
            ScrollView {
                OiConnectionStatus(remote: remote).padding(.horizontal, 20)
                if !remote.hasLoadedRemote {
                    if remote.loadError == nil { ProgressView("내 농장을 불러오는 중") }
                } else if remote.account == nil {
                    ContentUnavailableView {
                        Label("로그인이 필요해요", systemImage: "person")
                    } description: {
                        Text("로그인하면 내가 등록한 오이와 이야기를 볼 수 있어요.")
                    } actions: {
                        NavigationLink("로그인하기") { OiAccountView(remote: remote) }
                    }.padding(.top, 170)
                } else if remote.ownStories.isEmpty {
                    emptyFarm
                } else {
                    farmPlots(remote)
                }
            }
            .background(alignment: .top) {
                Image("MYFarmBackground").resizable().scaledToFit()
                    .opacity(isEmptyFarm ? 0.3 : 1)
                    .ignoresSafeArea(edges: .top).accessibilityHidden(true)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasPlots {
                    Text("* 내가 등록한 오이를 확인해보세요!")
                        .font(.custom("PearToucan-Regular", size: 20, relativeTo: .body))
                        .foregroundStyle(CampusStyle.sectionGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.vertical, 4)
                        .background(farmGround.ignoresSafeArea(edges: .bottom))
                }
            }
            .background(farmGround.ignoresSafeArea())
            .navigationTitle(hasPlots || isEmptyFarm ? "" : "내 농장")
            .toolbar {
                if hasPlots {
                    ToolbarItem(placement: .topBarTrailing) { farmTitle }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        } else {
            ContentUnavailableView("계정 연결이 필요해요", systemImage: "person", description: Text("로그인 후 내 농장을 확인해 주세요."))
        }
    }

    private var farmTitle: some View {
        Text("\(remote?.profile?.nickname ?? nickname)의 밭")
            .font(.custom("PearToucan-Regular", size: 35, relativeTo: .title))
            .foregroundStyle(Color(red: 126 / 255, green: 88 / 255, blue: 48 / 255))
            .lineLimit(1).minimumScaleFactor(0.6).accessibilityAddTraits(.isHeader)
    }

    private func farmPlots(_ remote: OiRemoteStore) -> some View {
        let stories = remote.ownStories
        return LazyVStack(spacing: 24) {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(stories) { story in farmCucumber(story, remote: remote).frame(maxWidth: 300) }
            } else {
                ForEach(Array(stride(from: 0, to: stories.count, by: 2)), id: \.self) { index in
                    MYFarmPlotLayout {
                        farmCucumber(stories[index], remote: remote)
                        if index + 1 < stories.count {
                            farmCucumber(stories[index + 1], remote: remote, foregroundPlot: true)
                        }
                    }
                }
            }
        }.padding(.top, dynamicTypeSize.isAccessibilitySize ? 140 : 182)
            .padding(.bottom, 16)
    }

    private func farmCucumber(_ story: OiLiveStory, remote: OiRemoteStore, foregroundPlot: Bool = false) -> some View {
        NavigationLink { OiStoryManagement(remote: remote, storyID: story.id) } label: {
            VStack(spacing: 8) {
                farmPortrait(story.cucumberAsset, foregroundPlot: foregroundPlot)
                VStack(spacing: 4) {
                    Text(story.cucumberName).font(CampusStyle.medium(16))
                    Text(story.status.oiStatusTitle).font(CampusStyle.body(12))
                }.foregroundStyle(CampusStyle.sectionGreen)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(story.cucumberName), \(story.status.oiStatusTitle), 내 이야기 관리")
            .accessibilityIdentifier("my.farm.story.\(story.id.uuidString)")
    }

    private func farmPortrait(_ asset: String, foregroundPlot: Bool) -> some View {
        Color.clear.aspectRatio(155.0 / 243.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let scale = geometry.size.width / (foregroundPlot ? 188 : 155)
                    ZStack {
                        Image(foregroundPlot ? "MYFarmShadowTwo" : "MYFarmShadowOne").resizable()
                            .frame(width: (foregroundPlot ? 206 : 177) * scale,
                                   height: (foregroundPlot ? 78 : 63) * scale)
                            .position(x: (foregroundPlot ? 94 : 80.5) * scale,
                                      y: (foregroundPlot ? 270 : 231.5) * scale)
                        // Most service presets use a square transparent canvas. Size their artwork by the plot height.
                        Image(asset).resizable().scaledToFit()
                            .frame(width: max(geometry.size.width, geometry.size.height), height: geometry.size.height)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }.accessibilityHidden(true)
    }

    private var emptyFarm: some View {
        VStack(alignment: .leading, spacing: 30) {
            Image("MYEmptyCucumber").resizable().scaledToFit()
                .shadow(color: .black.opacity(0.4), radius: 15).frame(height: 277)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text("아직 기부한 오이가 없어요")
                .font(.custom("Paperlogy-7Bold", size: 30, relativeTo: .title))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text("안내된 정식 기부처의 절차를 따라 기부해요.\n작성 승인을 받은 계정에서 나만의 오이와 이야기를 만들 수 있어요.")
                .font(.custom("Paperlogy-3Light", size: 18, relativeTo: .body)).lineSpacing(5)
            Text("최소 기부금과 성장·보상 정책은 아직 정해지지 않았어요.")
                .font(.custom("Paperlogy-3Light", size: 14, relativeTo: .footnote))
            NavigationLink {
                if let remote { OiStoryListScreen(remote: remote) }
                else {
                    ContentUnavailableView("로그인이 필요해요", systemImage: "person")
                }
            } label: { emptyAction }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
        }.foregroundStyle(Color(red: 39 / 255, green: 49 / 255, blue: 22 / 255))
            .padding(.horizontal, 38).padding(.vertical, 24)
    }

    private var emptyAction: some View {
        Text("기부하고 오이만들기").font(.custom("Paperlogy-6SemiBold", size: 25, relativeTo: .title2))
            .multilineTextAlignment(.center).foregroundStyle(.black)
            .padding(.horizontal, 20).padding(.vertical, 15)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 284, minHeight: 68)
            .background(.white, in: Capsule())
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 5)
    }

}

/// The two plot positions follow the reference scene while their size follows available width.
private struct MYFarmPlotLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 402
        let heights = subviews.enumerated().map { index, view in
            let size = view.sizeThatFits(ProposedViewSize(width: width * (index == 0 ? 155.0 / 402.0 : 188.0 / 402.0), height: nil))
            return size.height + (index == 0 ? 0 : width * 189 / 402)
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, view) in subviews.enumerated() {
            let width = bounds.width * (index == 0 ? 155.0 / 402.0 : 188.0 / 402.0)
            view.place(at: CGPoint(x: bounds.minX + bounds.width * (index == 0 ? 45.0 / 402.0 : 168.0 / 402.0),
                                   y: bounds.minY + (index == 0 ? 0 : bounds.width * 189 / 402)),
                       anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
        }
    }
}

#Preview("내 농장") { NavigationStack { MYFarmView() } }
