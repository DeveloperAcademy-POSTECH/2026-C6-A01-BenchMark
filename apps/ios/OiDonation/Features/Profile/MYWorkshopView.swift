//
//  MYWorkshopView.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import SwiftUI

struct MYWorkshopView: View {
    let demo: MYLibraryStore
    var remote: OiRemoteStore? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    private var isSignedIn: Bool { remote?.account != nil }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 402
            let sceneHeight = max(geometry.size.height, 874 * scale)
            let origin = CGPoint.zero
            ScrollView {
                ZStack {
                    Image("MYRoom").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: sceneHeight).clipped()
                    Group {
                        Image("MYRug").resizable().frame(width: 359 * scale, height: 122 * scale)
                            .position(x: origin.x + 178.5 * scale, y: origin.y + 783 * scale)
                        artwork("MYSofaShadow", rect: CGRect(x: -60, y: 646, width: 290, height: 72), scale: scale, origin: origin)
                        Image("MYSofa").resizable().scaledToFit().frame(width: 286 * scale, height: 237 * scale)
                            .rotationEffect(.degrees(-2.22))
                            .position(x: origin.x + 86.5 * scale, y: origin.y + 603 * scale)
                    }.accessibilityHidden(true)
                    Group {
                        NavigationLink(value: MYDestination.farm) {
                            Image("MYFarmWindow").resizable().scaledToFit().frame(width: 174 * scale, height: 278 * scale)
                        }.buttonStyle(.plain).position(x: 99 * scale, y: 315.5 * scale).accessibilityLabel("내 농장 보기").accessibilityIdentifier("my.farm")
                        NavigationLink(value: MYDestination.collection) {
                            Image("MYCollection").resizable().scaledToFit().frame(width: 163 * scale, height: 231 * scale)
                        }.buttonStyle(.plain).position(x: 301.5 * scale, y: 296 * scale).accessibilityLabel("오이 도감").accessibilityIdentifier("my.collection")
                        artwork("MYFarmerShadow", rect: CGRect(x: 54.8, y: 745.1, width: 244, height: 70), scale: scale, origin: origin)
                            .opacity(0.3).accessibilityHidden(true)
                        NavigationLink {
                            MYFarmerCustomizationView(remote: remote)
                                .id(remote?.account?.id)
                        } label: {
                            MYFarmerArtwork(ownerID: remote?.account?.id, outfit: remote?.farmerOutfit)
                                .frame(width: 264 * scale, height: 352 * scale)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .position(x: origin.x + 170 * scale, y: origin.y + 625 * scale)
                            .accessibilityLabel("\(remote?.profile?.farmName ?? "오이")의 농부 꾸미기")
                            .accessibilityIdentifier("my.farmer.customize")
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("농부를 꾸미려면\n캐릭터를 눌러주세요!")
                                .font(.custom("Paperlogy-3Light", size: 16, relativeTo: .body))
                                .foregroundStyle(Color(red: 1, green: 236 / 255, blue: 221 / 255))
                                .frame(maxWidth: 150).fixedSize(horizontal: false, vertical: true)
                                .position(x: origin.x + 302 * scale, y: origin.y + 698 * scale)
                                .allowsHitTesting(false)
                        }
                    }.disabled(!isSignedIn).accessibilityHidden(!isSignedIn)
                    if !isSignedIn {
                        Color.white.opacity(0.8).allowsHitTesting(false)
                        if !dynamicTypeSize.isAccessibilitySize { guestMessage(scale: scale) }
                    }
                    NavigationLink { MYSettingsView(demo: demo, remote: remote) } label: {
                        ZStack {
                            Image("MYSettingsBoard").resizable().scaledToFit()
                            Image("MYRake").resizable().scaledToFit().frame(width: 68 * scale, height: 172.7 * scale)
                            Text("설\n정").font(.custom("PearToucan-Regular", size: 20, relativeTo: .body)).dynamicTypeSize(.medium).lineSpacing(0)
                                .foregroundStyle(Color(red: 0.47, green: 0.25, blue: 0.08))
                                .position(x: 71.06 * scale, y: 30.5 * scale)
                        }.frame(width: 91.76 * scale, height: 191.2 * scale)
                    }.buttonStyle(.plain).position(x: 318.82 * scale, y: 528.1 * scale).accessibilityLabel("설정").accessibilityIdentifier("my.settings")

                    Button { dismiss() } label: {
                        Image("MYExitDoor").resizable().scaledToFit().frame(width: 50, height: 50)
                            .frame(width: 66, height: 66).contentShape(Circle())
                    }.buttonStyle(.plain).glassEffect(.regular.tint(.orange.opacity(0.15)).interactive(), in: Circle())
                        .position(x: 45 * scale, y: 99 * scale)
                        .accessibilityLabel("MY 닫기").accessibilityIdentifier("my.close")
                    if isSignedIn && !dynamicTypeSize.isAccessibilitySize {
                        workshopTitle.frame(maxWidth: max(0, geometry.size.width - 180))
                            .position(x: geometry.size.width / 2, y: 97.5 * scale)
                        addSeedLink.position(x: geometry.size.width - 55 * scale, y: 97.5 * scale)
                    }
                }.frame(width: geometry.size.width, height: sceneHeight).clipped()
            }.scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarRole(.navigationStack)
        .safeAreaInset(edge: .bottom) {
            if dynamicTypeSize.isAccessibilitySize {
                if isSignedIn {
                    workshopTitle
                    addSeedLink
                }
                else {
                    Text("MY 페이지는 로그인 후 사용할 수 있습니다")
                        .font(CampusStyle.medium(22)).multilineTextAlignment(.center).padding(.horizontal, 20)
                }
                NavigationLink(isSignedIn ? "농부 꾸미기" : "로그인하기") {
                    if isSignedIn { MYFarmerCustomizationView(remote: remote).id(remote?.account?.id) }
                    else { MYSettingsView(demo: demo, remote: remote) }
                }
                    .font(.body).padding(12).background(.regularMaterial, in: Capsule()).padding(.bottom, 8)
            }
        }
    }

    private var addSeedLink: some View {
        NavigationLink { OiEvidenceDesignPreview() } label: {
            OiSeedBalanceLabel(count: 0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("my.workshop.addSeed")
    }

    private var workshopTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(remote?.profile?.farmName ?? "오이").font(.custom("PearToucan-Regular", size: 35, relativeTo: .title))
            Text("의 작업실").font(.custom("PearToucan-Light", size: 20, relativeTo: .body))
        }.foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }

    private func guestMessage(scale: CGFloat) -> some View {
        Group {
            Text("MY 페이지는\n로그인 후\n사용할 수 있습니다")
                .font(.custom("Paperlogy-6SemiBold", size: 30, relativeTo: .title))
                .tracking(0.6).lineSpacing(9).multilineTextAlignment(.center)
                .foregroundStyle(Color(red: 132 / 255, green: 64 / 255, blue: 4 / 255))
                .frame(width: 300 * scale)
                .position(x: 201 * scale, y: 295.5 * scale)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize {
                Text("로그인 하러 가기!").font(CampusStyle.medium(20)).tracking(0.4)
                    .rotationEffect(.degrees(-12.81))
                    .position(x: 134.56 * scale, y: 473 * scale)
                Image("MYLoginArrow").resizable().scaledToFit()
                    .frame(width: 67 * scale, height: 28 * scale)
                    .rotationEffect(.degrees(17.34))
                    .position(x: 249.15 * scale, y: 455.35 * scale)
            }
        }.allowsHitTesting(false)
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
