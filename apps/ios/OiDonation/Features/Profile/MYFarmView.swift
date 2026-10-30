// Created by 이돈혁

import SwiftUI

struct MYFarmView: View {
    var remote: OiRemoteStore? = nil
    var nickname = "신서임당"
    var showsEmptyExample = false

    var body: some View {
        if let remote {
            ScrollView {
                if !remote.hasLoadedRemote || remote.account == nil || !remote.ownStories.isEmpty {
                    Image("MYFarmBackground").resizable().scaledToFit().accessibilityHidden(true)
                }
                OiConnectionStatus(remote: remote).padding(.horizontal, 20)
                if !remote.hasLoadedRemote {
                    if remote.loadError == nil { ProgressView("내 농장을 불러오는 중") }
                } else if remote.account == nil {
                    ContentUnavailableView("로그인이 필요해요", systemImage: "person", description: Text("계정 메뉴에서 로그인하면 등록한 오이를 볼 수 있어요."))
                } else if remote.ownStories.isEmpty {
                    emptyFarm
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 20) {
                        ForEach(remote.ownStories) { story in
                            NavigationLink { OiStoryManagement(remote: remote, storyID: story.id) } label: {
                                VStack {
                                    Image(story.cucumberAsset).resizable().scaledToFit().frame(height: 220)
                                    Text(story.cucumberName).font(.headline)
                                    Text(story.status.oiStatusTitle).font(.caption)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(20)
                }
            }
            .background(remote.hasLoadedRemote && remote.account != nil && remote.ownStories.isEmpty ? Color.white : Color(red: 193 / 255, green: 215 / 255, blue: 72 / 255))
            .navigationTitle("내 농장")
            .toolbar { ToolbarItem(placement: .principal) { farmTitle } }.navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        } else if showsEmptyExample {
            ScrollView { emptyFarm }.background(Color.white)
                .toolbar { ToolbarItem(placement: .principal) { farmTitle } }
        } else { exampleFarm }
    }

    private var exampleFarm: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            ZStack(alignment: .top) {
                Color(red: 193 / 255, green: 215 / 255, blue: 72 / 255)
                Image("MYFarmBackground").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.width * 462 / 402).clipped()
                Group {
                    Image("MYFarmShadowOne").resizable().scaledToFit().frame(width: 177 * scale, height: 63 * scale)
                        .position(x: geometry.size.width / 2 - 75.5 * scale, y: 529.5 * scale)
                    Image("MYFarmShadowTwo").resizable().scaledToFit().frame(width: 206 * scale, height: 78 * scale)
                        .position(x: geometry.size.width / 2 + 61 * scale, y: 757 * scale)
                }.accessibilityHidden(true)
                Image("MYFarmPostech").resizable().scaledToFit().frame(width: 155 * scale, height: 243 * scale)
                    .position(x: geometry.size.width / 2 - 78.5 * scale, y: 419.5 * scale)
                    .accessibilityLabel("POSTECH 잠바를 입은 디자인 예시 오이")
                Image("MYFarmGardener").resizable().scaledToFit().frame(width: 188 * scale, height: 295 * scale)
                    .position(x: geometry.size.width / 2 + 61 * scale, y: 634.5 * scale)
                    .accessibilityLabel("멜빵바지를 입은 디자인 예시 오이")
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .ignoresSafeArea()
        .navigationTitle("내 농장")
        .toolbar { ToolbarItem(placement: .principal) { farmTitle } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        .toolbarRole(.navigationStack)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Text("* 내가 기부한 오이를 확인해보세요!").font(.custom("PearToucan-Regular", size: 20, relativeTo: .body))
                    .foregroundStyle(Color(red: 135 / 255, green: 160 / 255, blue: 0))
                Text("디자인 예시 · 실제 기부 내역이 아니에요").font(.caption2)
            }
                .padding(8).background(.thinMaterial, in: Capsule()).padding(.bottom, 8)
        }
    }
    private var farmTitle: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            Text("\(remote?.profile?.nickname ?? nickname)의").font(.custom("PearToucan-Light", size: 20, relativeTo: .body))
            Text("쉬쏘밭").font(.custom("PearToucan-Regular", size: 35, relativeTo: .title))
        }.foregroundStyle(Color(red: 126 / 255, green: 88 / 255, blue: 48 / 255))
            .lineLimit(1).minimumScaleFactor(0.6).accessibilityElement(children: .combine)
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
                if let remote { OiAccountView(remote: remote) }
                else {
                    ContentUnavailableView("서비스 모드에서 이용해 주세요", systemImage: "leaf", description: Text("이 화면은 디자인 예시예요. 실제 기부 안내·증빙 제출·작성 승인은 서비스 모드의 계정 메뉴에서 확인할 수 있어요."))
                }
            } label: { emptyAction }
            if remote == nil { Text("디자인 예시 · 실제 기부 내역이 아니에요").font(.caption) }
        }.foregroundStyle(Color(red: 39 / 255, green: 49 / 255, blue: 22 / 255))
            .padding(.horizontal, 38).padding(.vertical, 24)
    }

    private var emptyAction: some View {
        Text("기부하고 오이만들기").font(.custom("Paperlogy-6SemiBold", size: 25, relativeTo: .title2))
            .padding(.horizontal, 20).padding(.vertical, 15).frame(maxWidth: .infinity)
            .background(.white, in: Capsule()).shadow(color: .black.opacity(0.2), radius: 5)
    }

}

#Preview("내 농장") { NavigationStack { MYFarmView() } }

#Preview("빈 농장") { NavigationStack { MYFarmView(showsEmptyExample: true) } }
