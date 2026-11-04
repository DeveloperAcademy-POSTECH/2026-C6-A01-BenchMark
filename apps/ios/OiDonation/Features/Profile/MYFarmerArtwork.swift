//
//  MYFarmerArtwork.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import SwiftUI

struct MYFarmerArtwork: View {
    let ownerID: UUID?
    @AppStorage private var storedAppearance: String

    init(ownerID: UUID?) {
        self.ownerID = ownerID
        _storedAppearance = AppStorage(wrappedValue: MYFarmerAppearance.classic.rawValue,
                                      MYFarmerAppearanceStore.key(ownerID: ownerID))
    }

    var body: some View {
        MYFarmerPresetArtwork(appearance: ownerID == nil ? .classic : MYFarmerAppearance(rawValue: storedAppearance) ?? .classic)
    }
}

struct MYFarmerPresetArtwork: View {
    let appearance: MYFarmerAppearance

    var body: some View {
        Group {
            if appearance == .classic {
                Image("OiFarmer").resizable().scaledToFit()
            } else {
                GeometryReader { geometry in
                    let scale = geometry.size.width / 200
                    ZStack(alignment: .topLeading) {
                        layer("MYFarmerCasualBody", size: geometry.size)
                        layer("MYFarmerCasualShoes", size: geometry.size)
                        layer("MYFarmerCasualPants", size: CGSize(width: geometry.size.width * 0.9239,
                                                                  height: geometry.size.height * 0.9239))
                            .offset(x: geometry.size.width * 0.0376, y: geometry.size.height * 0.0485)
                        layer("MYFarmerCasualShirt", size: geometry.size)
                        Image("MYFarmerCasualGlasses").resizable()
                            .frame(width: 66.88 * scale, height: 33.44 * scale)
                            .rotationEffect(.degrees(-15.89))
                            .position(x: 94.44 * scale, y: 79.04 * scale)
                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }.aspectRatio(200.0 / 277.0, contentMode: .fit)
            }
        }.accessibilityHidden(true)
    }

    private func layer(_ name: String, size: CGSize) -> some View {
        Image(name).resizable().frame(width: size.width, height: size.height)
    }
}

struct MYFarmerCustomizationView: View {
    let ownerID: UUID?
    @State private var selection: MYFarmerAppearance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(ownerID: UUID?) {
        self.ownerID = ownerID
        _selection = State(initialValue: MYFarmerAppearanceStore.read(ownerID: ownerID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Button("저장") {
                        MYFarmerAppearanceStore.save(selection, ownerID: ownerID)
                        dismiss()
                    }
                    .font(CampusStyle.medium(20)).foregroundStyle(.white)
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .background(CampusStyle.green, in: Capsule())
                    .disabled(ownerID == nil).accessibilityIdentifier("my.farmer.save")
                    Button("되돌리기") { selection = MYFarmerAppearanceStore.read(ownerID: ownerID) }
                        .font(CampusStyle.medium(14)).underline().foregroundStyle(.secondary)
                        .frame(minHeight: 44).accessibilityIdentifier("my.farmer.reset")
                    Spacer(minLength: 0)
                }
                MYFarmerPresetArtwork(appearance: selection)
                    .frame(maxWidth: .infinity).frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 277)
                    .accessibilityElement(children: .ignore).accessibilityHidden(false).accessibilityLabel(selection.title)
                Text(selection.detail).font(CampusStyle.medium(14)).foregroundStyle(CampusStyle.sectionGreen)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                Text("세트").font(.custom("Paperlogy-7Bold", size: 16, relativeTo: .headline))
                    .foregroundStyle(CampusStyle.green).padding(.bottom, 5)
                    .overlay(alignment: .bottom) { Rectangle().fill(CampusStyle.green).frame(height: 2) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 16) {
                    ForEach(MYFarmerAppearance.allCases) { appearance in
                        Button { selection = appearance } label: {
                            VStack(spacing: 10) {
                                MYFarmerPresetArtwork(appearance: appearance).frame(height: 150)
                                HStack {
                                    Text(appearance.title).font(CampusStyle.medium(14))
                                    if selection == appearance { Image(systemName: "checkmark.circle.fill") }
                                }
                            }.foregroundStyle(CampusStyle.sectionGreen)
                                .padding(12).frame(maxWidth: .infinity)
                                .background(Color(white: 0.975), in: RoundedRectangle(cornerRadius: 10))
                                .overlay { RoundedRectangle(cornerRadius: 10).stroke(selection == appearance ? CampusStyle.green : .clear, lineWidth: 2) }
                        }.buttonStyle(.plain).disabled(ownerID == nil)
                            .accessibilityAddTraits(selection == appearance ? .isSelected : [])
                            .accessibilityIdentifier("my.farmer.\(appearance.rawValue)")
                    }
                }
                Text(ownerID == nil ? "로그인하면 이 기기에 농부 모습을 저장할 수 있어요." : "선택한 모습은 이 기기의 내 작업실과 지도에 적용돼요.")
                    .font(CampusStyle.body(14)).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(Color.white).navigationTitle("농부 꾸미기").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

#Preview("농부 꾸미기") { NavigationStack { MYFarmerCustomizationView(ownerID: nil) } }
