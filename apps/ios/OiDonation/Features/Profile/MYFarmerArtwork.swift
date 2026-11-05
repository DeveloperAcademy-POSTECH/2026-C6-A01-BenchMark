//
//  MYFarmerArtwork.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import SwiftUI

struct MYFarmerArtwork: View {
    let ownerID: UUID?
    let outfit: OiFarmerOutfit?
    @AppStorage private var storedAppearance: String

    init(ownerID: UUID?, outfit: OiFarmerOutfit? = nil) {
        self.ownerID = ownerID
        self.outfit = outfit
        _storedAppearance = AppStorage(wrappedValue: MYFarmerAppearance.classic.rawValue,
                                      MYFarmerAppearanceStore.key(ownerID: ownerID))
    }

    var body: some View {
        Group {
            if ownerID != nil, let outfit, case .success(let wardrobe) = MYFarmerWardrobe.loaded, wardrobe.validates(outfit) {
                MYFarmerLayeredArtwork(outfit: outfit, wardrobe: wardrobe)
            } else {
                MYFarmerPresetArtwork(appearance: ownerID == nil ? .classic : MYFarmerAppearance(rawValue: storedAppearance) ?? .classic)
            }
        }
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
