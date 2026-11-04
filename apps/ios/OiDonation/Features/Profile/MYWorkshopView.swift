// Created by 이돈혁

import SwiftUI

struct MYWorkshopView: View {
    let demo: MYLibraryStore
    var remote: OiRemoteStore? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            let origin = CGPoint(x: (geometry.size.width - 402 * scale) / 2, y: (geometry.size.height - 874 * scale) / 2)
            ZStack {
                Image("MYRoom").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                Group {
                    Image("MYRug").resizable().frame(width: 359 * scale, height: 122 * scale)
                        .position(x: origin.x + 178.5 * scale, y: origin.y + 783 * scale)
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
                NavigationLink { MYSettingsView(demo: demo, remote: remote) } label: {
                    ZStack {
                        artwork("MYSettingsBoard", rect: CGRect(x: 272.94, y: 432.5, width: 91.76, height: 191.2), scale: scale, origin: origin)
                        artwork("MYRake", rect: CGRect(x: 284.69, y: 441.27, width: 68, height: 172.7), scale: scale, origin: origin)
                        Text("설\n정").font(.custom("PearToucan-Regular", size: 20, relativeTo: .body)).dynamicTypeSize(.medium).lineSpacing(0)
                            .foregroundStyle(Color(red: 0.47, green: 0.25, blue: 0.08))
                            .position(x: origin.x + 344 * scale, y: origin.y + 463 * scale)
                    }
                }.buttonStyle(.plain).accessibilityLabel("설정").accessibilityIdentifier("my.settings")
                artwork("MYFarmerShadow", rect: CGRect(x: 54.8, y: 745.1, width: 244, height: 70), scale: scale, origin: origin)
                    .opacity(0.3).accessibilityHidden(true)
                NavigationLink {
                    MYFarmerCustomizationView(ownerID: remote?.account?.id)
                        .id(remote?.account?.id)
                } label: {
                    MYFarmerArtwork(ownerID: remote?.account?.id)
                        .frame(width: 264 * scale, height: 352 * scale)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .position(x: origin.x + 170 * scale, y: origin.y + 625 * scale)
                    .accessibilityLabel("\(demo.nickname)의 농부 꾸미기")
                    .accessibilityIdentifier("my.farmer.customize")
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("농부를 꾸미려면\n캐릭터를 눌러주세요!")
                        .font(.custom("Paperlogy-3Light", size: 16, relativeTo: .body))
                        .foregroundStyle(Color(red: 1, green: 236 / 255, blue: 221 / 255))
                        .frame(maxWidth: 150).fixedSize(horizontal: false, vertical: true)
                        .position(x: origin.x + 302 * scale, y: origin.y + 698 * scale)
                        .allowsHitTesting(false)
                }
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
        .safeAreaInset(edge: .bottom) {
            if dynamicTypeSize.isAccessibilitySize {
                NavigationLink("농부 꾸미기") { MYFarmerCustomizationView(ownerID: remote?.account?.id).id(remote?.account?.id) }
                    .font(.body).padding(12).background(.regularMaterial, in: Capsule()).padding(.bottom, 8)
            }
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
    NavigationStack { MYWorkshopView(demo: MYLibraryStore()) }
}
#Preview("MY 작은 화면", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack { MYWorkshopView(demo: MYLibraryStore()) }
}
#Preview("MY 큰 화면", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack { MYWorkshopView(demo: MYLibraryStore()) }
}
