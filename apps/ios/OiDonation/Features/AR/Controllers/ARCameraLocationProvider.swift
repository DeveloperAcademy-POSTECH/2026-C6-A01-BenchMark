//
//  ARCameraLocationProvider.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/15/26.
//

import CoreLocation

/// Injectable location input; current user coordinates remain on this device.
@MainActor protocol ARCameraLocationProviding: AnyObject {
    var location: CLLocation? { get }
    var hasUsableFix: Bool { get }
    var hasPreciseLocationPermission: Bool { get }
    var message: String? { get }
    func start()
    func stop()
}

extension CampusGeoLocation: ARCameraLocationProviding {}
