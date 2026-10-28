// Created by 이돈혁

import SwiftUI

struct MYWorkshopView: View {
    let container: AppContainer
    let store: CampusStoryStore
    let demo: MYDemoStore
    let onCamera: () -> Void
    var remote: OiRemoteStore? = nil
    @State private var showingSettings = false

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            let origin = CGPoint(x: (geometry.size.width - 402 * scale) / 2, y: (geometry.size.height - 874 * scale) / 2)
            ZStack {
                Image("MYRoom").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                Group {
                    Image("MYRug").resizable().frame(width: 359 * scale, height: 122 * scale)
                        .position(x: origin.x + 203.5 * scale, y: origin.y + 775 * scale)
                    artwork("MYSofaShadow", rect: CGRect(x: -60, y: 646, width: 290, height: 72), scale: scale, origin: origin)
                    Image("MYSofa").resizable().scaledToFit().frame(width: 286 * scale, height: 237 * scale)
                        .rotationEffect(.degrees(-2.22))
                        .position(x: origin.x + 86.5 * scale, y: origin.y + 603 * scale)
                }.accessibilityHidden(true)
                NavigationLink(value: MYDestination.farm) {
                    artwork("MYFarmWindow", rect: CGRect(x: 12, y: 176.5, width: 174, height: 278), scale: scale, origin: origin)
                }.buttonStyle(.plain).accessibilityLabel("내 농장 보기").accessibilityIdentifier("my.farm")
                NavigationLink(value: MYDestination.collection) {
                    artwork("MYCollection", rect: CGRect(x: 220, y: 180.5, width: 163, height: 231), scale: scale, origin: origin)
                }.buttonStyle(.plain).accessibilityLabel("오이 도감").accessibilityIdentifier("my.collection")
                Button { showingSettings = true } label: {
                    ZStack {
                        artwork("MYSettingsBoard", rect: CGRect(x: 281, y: 432.5, width: 92, height: 192), scale: scale, origin: origin)
                        artwork("MYRake", rect: CGRect(x: 292.7, y: 441.3, width: 68, height: 173), scale: scale, origin: origin)
                        Text("설\n정").font(.custom("PearToucan-Regular", size: 20, relativeTo: .body)).dynamicTypeSize(.medium).lineSpacing(0)
                            .foregroundStyle(Color(red: 0.47, green: 0.25, blue: 0.08))
                            .position(x: origin.x + 352 * scale, y: origin.y + 463 * scale)
                    }
                }.buttonStyle(.plain).accessibilityLabel("설정과 기존 메뉴").accessibilityIdentifier("my.settings")
                artwork("MYFarmerShadow", rect: CGRect(x: 82, y: 737, width: 244, height: 70), scale: scale, origin: origin)
                    .accessibilityHidden(true)
                artwork("OiFarmer", rect: CGRect(x: 63, y: 441, width: 264, height: 352), scale: scale, origin: origin)
                    .accessibilityLabel("\(demo.nickname)의 농부 캐릭터")
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        .toolbarRole(.navigationStack)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(demo.nickname).font(.custom("PearToucan-Regular", size: 35, relativeTo: .title))
                    Text("의 작업실").font(.custom("PearToucan-Light", size: 20, relativeTo: .body))
                }.foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6).accessibilityElement(children: .combine)
            }
        }
        .sheet(isPresented: $showingSettings) { CampusProfileMenu(container: container, store: store, onCamera: onCamera, remote: remote).id(remote?.account?.id) }
        .safeAreaInset(edge: .bottom) {
            Text(remote == nil ? "디자인 예시 · 더미 프로필" : "농부의 옷·아이템 꾸미기는 준비 중이에요").font(.caption2)
                .padding(8).background(.thinMaterial, in: Capsule()).padding(.bottom, 8)
        }
    }

    private func artwork(_ name: String, rect: CGRect, scale: CGFloat, origin: CGPoint) -> some View {
        Image(name).resizable().scaledToFit()
            .frame(width: rect.width * scale, height: rect.height * scale)
            .contentShape(Rectangle())
            .position(x: origin.x + rect.midX * scale, y: origin.y + rect.midY * scale)
    }
}

#Preview("MY 기준", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack { MYWorkshopView(container: .preview, store: CampusStoryStore(), demo: MYDemoStore(), onCamera: {}) }
}
#Preview("MY 작은 화면", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack { MYWorkshopView(container: .preview, store: CampusStoryStore(), demo: MYDemoStore(), onCamera: {}) }
}
#Preview("MY 큰 화면", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack { MYWorkshopView(container: .preview, store: CampusStoryStore(), demo: MYDemoStore(), onCamera: {}) }
}
