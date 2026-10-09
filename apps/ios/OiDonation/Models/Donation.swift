//
//  Donation.swift
//  OiDonation
//
//  Created by jiwon hong on 10/9/26.
//

import Foundation

struct Donation: Identifiable {
    let id: UUID
    let donorID: UUID
    let organizationID: UUID
    let donatedAt: Date
    let amount: Int
    let status: DonationStatus
}

enum DonationStatus {
    case submitted
    case underReview
    case approved
    case plaqueInProduction
    case installed

    var displayedStatus: String {
        switch self {
        case .submitted: "신청 완료"
        case .underReview: "신청 검토"
        case .approved: "신청 승인"
        case .plaqueInProduction: "명패 제작"
        case .installed: "설치 완료"
        }

    }
}
