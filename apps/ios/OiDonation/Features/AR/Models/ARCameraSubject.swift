//
//  ARCameraSubject.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/15/26.
//

import Foundation
import RealityKit
import UIKit

/// A fixed photo subject supplied by another feature, independent of the legacy mascot picker.
@MainActor
struct ARCameraSubject: Identifiable {
    let id: UUID
    let title: String
    let heightMeters: Float
    var placement: CampusPlacement? = nil
    var loadThumbnail: (@MainActor () async throws -> UIImage)? = nil
    let loadModel: @MainActor () async throws -> Entity

    var defaultSettings: ARCaptureSettings {
        var value = ARCaptureSettings()
        value.height = heightMeters.isFinite ? min(2.5, max(0.2, heightMeters)) : 1.5
        if let placement { value.rotation = Float(180 - placement.headingDegrees) }
        value.cucumberStoryID = id
        value.cucumberName = title
        return value
    }
}
