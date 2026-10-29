// Created by 이돈혁

import SwiftUI

struct MYFarmView: View {
    var remote: OiRemoteStore? = nil

    var body: some View {
        if let remote {
            ScrollView {
                Image("MYFarmBackground").resizable().scaledToFit().accessibilityHidden(true)
                OiConnectionStatus(remote: remote).padding(.horizontal, 20)
                if !remote.hasLoadedRemote {
                    if remote.loadError == nil { ProgressView("내 농장을 불러오는 중") }
                } else if remote.account == nil {
                    ContentUnavailableView("로그인이 필요해요", systemImage: "person", description: Text("계정 메뉴에서 로그인하면 등록한 오이를 볼 수 있어요."))
                } else if remote.ownStories.isEmpty {
                    ContentUnavailableView("아직 등록한 오이가 없어요", systemImage: "leaf", description: Text("작성 승인 후 내 이야기에서 오이를 만들어 보세요."))
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
            .background(Color(red: 193 / 255, green: 215 / 255, blue: 72 / 255))
            .navigationTitle("내 농장").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
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
                        .position(x: geometry.size.width / 2 - 75.5 * scale, y: 546.5 * scale)
                    Image("MYFarmShadowTwo").resizable().scaledToFit().frame(width: 206 * scale, height: 78 * scale)
                        .position(x: geometry.size.width / 2 + 61 * scale, y: 774 * scale)
                }.accessibilityHidden(true)
                Image("MYFarmPostech").resizable().scaledToFit().frame(width: 155 * scale, height: 243 * scale)
                    .position(x: geometry.size.width / 2 - 78.5 * scale, y: 436.5 * scale)
                    .accessibilityLabel("POSTECH 잠바를 입은 디자인 예시 오이")
                Image("MYFarmGardener").resizable().scaledToFit().frame(width: 188 * scale, height: 295 * scale)
                    .position(x: geometry.size.width / 2 + 61 * scale, y: 651.5 * scale)
                    .accessibilityLabel("멜빵바지를 입은 디자인 예시 오이")
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .ignoresSafeArea()
        .navigationTitle("내 농장")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        .toolbarRole(.navigationStack)
        .safeAreaInset(edge: .bottom) {
            Text("디자인 예시 · 실제 기부 내역이 아니에요").font(.caption2)
                .padding(8).background(.thinMaterial, in: Capsule()).padding(.bottom, 8)
        }
    }
}

#Preview("내 농장") { NavigationStack { MYFarmView() } }
