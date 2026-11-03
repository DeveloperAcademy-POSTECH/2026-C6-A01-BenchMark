// Created by 이돈혁

import SwiftUI

struct MYFarmView: View {
    var remote: OiRemoteStore? = nil
    var nickname = "농부"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let remote {
            ScrollView {
                OiConnectionStatus(remote: remote).padding(.horizontal, 20).padding(.top, 10)
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
                if !remote.hasLoadedRemote || remote.account == nil || !remote.ownStories.isEmpty {
                    Image("MYFarmBackground").resizable().scaledToFit()
                        .ignoresSafeArea(edges: .top).accessibilityHidden(true)
                }
            }
            .background(remote.hasLoadedRemote && remote.account != nil && remote.ownStories.isEmpty ? Color.white : Color(red: 193 / 255, green: 215 / 255, blue: 72 / 255))
            .navigationTitle("내 농장")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { farmTitle } }.navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        } else {
            ContentUnavailableView("계정 연결이 필요해요", systemImage: "person", description: Text("로그인 후 내 농장을 확인해 주세요."))
        }
    }

    private var farmTitle: some View {
        Text("\(remote?.profile?.nickname ?? nickname)의 밭")
            .font(.custom("PearToucan-Regular", size: 35, relativeTo: .title))
            .foregroundStyle(Color(red: 126 / 255, green: 88 / 255, blue: 48 / 255))
            .lineLimit(1).minimumScaleFactor(0.6).accessibilityElement(children: .combine)
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
                            farmCucumber(stories[index + 1], remote: remote)
                        }
                    }
                }
            }
            Text("* 내가 등록한 오이를 확인해보세요!")
                .font(.custom("PearToucan-Regular", size: 20, relativeTo: .body))
                .foregroundStyle(CampusStyle.sectionGreen).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.bottom, 16)
        }.padding(.top, dynamicTypeSize.isAccessibilitySize ? 140 : 182)
    }

    private func farmCucumber(_ story: OiLiveStory, remote: OiRemoteStore) -> some View {
        NavigationLink { OiStoryManagement(remote: remote, storyID: story.id) } label: {
            VStack(spacing: 8) {
                Image(story.cucumberAsset).resizable().scaledToFit()
                    .aspectRatio(155.0 / 243.0, contentMode: .fit)
                    .background(alignment: .bottom) {
                        Ellipse().fill(.black.opacity(0.28)).frame(height: 18).blur(radius: 10).padding(.horizontal, 12)
                    }.accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text(story.cucumberName).font(CampusStyle.medium(16))
                    Text(story.status.oiStatusTitle).font(CampusStyle.body(12))
                }.foregroundStyle(CampusStyle.sectionGreen)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            }
        }.buttonStyle(.plain)
            .accessibilityLabel("\(story.cucumberName), \(story.status.oiStatusTitle), 내 이야기 관리")
            .accessibilityIdentifier("my.farm.story.\(story.id.uuidString)")
    }

    private var emptyFarm: some View {
        VStack(alignment: .leading, spacing: 30) {
            Image("MYEmptyCucumber").resizable().scaledToFit().frame(height: 277)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text("아직 기부한 오이가 없어요")
                .font(.custom("Paperlogy-6SemiBold", size: 30, relativeTo: .title))
                .frame(maxWidth: .infinity)
            Text("1. 안내된 정식 기부처의 절차를 따라 기부해요.\n2. 기부 증빙을 제출하고 운영자 검토를 기다려요.\n3. 글 작성 승인 후 나만의 오이와 이야기를 만들어요.")
                .font(.custom("Paperlogy-4Regular", size: 18, relativeTo: .body)).lineSpacing(5)
            Text("최소 기부금과 성장·보상 정책은 아직 정해지지 않았어요. 작성 승인은 학교의 공식 납입 확인·영수증 발급과 별개예요.")
                .font(.custom("Paperlogy-4Regular", size: 14, relativeTo: .footnote))
            NavigationLink {
                if let remote { OiStoryListScreen(remote: remote) }
                else {
                    ContentUnavailableView("로그인이 필요해요", systemImage: "person")
                }
            } label: { emptyAction }
        }.foregroundStyle(Color(red: 39 / 255, green: 49 / 255, blue: 22 / 255))
            .padding(.horizontal, 38).padding(.vertical, 24)
    }

    private var emptyAction: some View {
        Text("기부하고 오이만들기").font(.custom("Paperlogy-6SemiBold", size: 25, relativeTo: .title2))
            .padding(.horizontal, 20).padding(.vertical, 15).frame(maxWidth: .infinity)
            .background(.white, in: Capsule()).shadow(color: .black.opacity(0.2), radius: 5)
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
