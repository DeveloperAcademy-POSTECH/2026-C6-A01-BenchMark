//
//  Story.swift
//  OiDonation
//
//  Created by jiwon hong on 10/9/26.
//

import Foundation

struct Story: Identifiable, Sendable {
    var id: String { plaqueID }
    let plaqueID: String
    let donorID: UUID
    let title: String
    let content: String
}
