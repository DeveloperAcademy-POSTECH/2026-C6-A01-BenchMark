//
//  MYFarmerAppearanceStore.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import Foundation

enum MYFarmerAppearance: String, CaseIterable, Identifiable {
    case classic, casual

    var id: String { rawValue }
    var title: String { self == .classic ? "농부 세트" : "큐 기본 세트" }
    var detail: String {
        self == .classic ? "농부 모자 · 멜빵바지" : "흰색 반팔티 · 남색 운동복 · 흰색 컨버스 · 로즈골드 안경"
    }
}

/// Local artwork preferences never change a public story or another person's cucumber.
enum MYFarmerAppearanceStore {
    static func key(ownerID: UUID?) -> String {
        "oi.farmerAppearance.v1." + (ownerID?.uuidString.lowercased() ?? "signed-out")
    }

    static func read(ownerID: UUID?, defaults: UserDefaults = .standard) -> MYFarmerAppearance {
        guard ownerID != nil, let value = defaults.string(forKey: key(ownerID: ownerID)) else { return .classic }
        return MYFarmerAppearance(rawValue: value) ?? .classic
    }

    static func save(_ appearance: MYFarmerAppearance, ownerID: UUID?, defaults: UserDefaults = .standard) {
        guard ownerID != nil else { return }
        defaults.set(appearance.rawValue, forKey: key(ownerID: ownerID))
    }
}
