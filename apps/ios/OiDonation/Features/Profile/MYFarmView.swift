// Created by 이돈혁

import SwiftUI

struct MYFarmView: View {
    var remote: OiRemoteStore? = nil
    var nickname = "농부"

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
        } else {
            ContentUnavailableView("계정 연결이 필요해요", systemImage: "person", description: Text("로그인 후 내 농장을 확인해 주세요."))
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

#Preview("내 농장") { NavigationStack { MYFarmView() } }
