//
//  Untitled.swift
//  OiDonation
//
//  Created by jiwon hong on 10/9/26.
//

import Foundation

struct Donor: Identifiable {
    let id: UUID
    let displayIdentity: DonorDisplayIdentity
}

enum DonorDisplayIdentity {
    case name(String)
    case nickname(String)
    case anonymous

    var displayName: String {
        switch self {
        case .name(let name): return name
        case .nickname(let nickname): return nickname
        case .anonymous: return "익명"
        }
    }
}
