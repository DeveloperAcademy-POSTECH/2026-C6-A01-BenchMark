//
//  OiFeatureUsage.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/16/26.
//

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

enum OiAppFeature: String, CaseIterable {
    case notifications, location, camera, photos

    var title: String {
        switch self {
        case .notifications: "알림"
        case .location: "위치 정보"
        case .camera: "카메라"
        case .photos: "사진 저장"
        }
    }
}

enum OiFeatureUsageError: LocalizedError, Equatable {
    case disabled(OiAppFeature)

    var errorDescription: String? {
        switch self {
        case .disabled(let feature): "앱 설정에서 \(feature.title) 사용을 켜 주세요."
        }
    }
}

/// Device-local usage choices are separate from iOS authorization.
@MainActor @Observable final class OiFeatureUsage {
    static let shared = OiFeatureUsage()
    static let didChange = Notification.Name("OiFeatureUsage.didChange")
    private let defaults: UserDefaults
    private var values: [OiAppFeature: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = Dictionary(uniqueKeysWithValues: OiAppFeature.allCases.map { feature in
            (feature, defaults.object(forKey: Self.key(feature)) as? Bool ?? true)
        })
    }

    func isEnabled(_ feature: OiAppFeature) -> Bool { values[feature] ?? true }

    func require(_ feature: OiAppFeature) throws {
        guard isEnabled(feature) else { throw OiFeatureUsageError.disabled(feature) }
    }

    func setEnabled(_ enabled: Bool, for feature: OiAppFeature) {
        guard isEnabled(feature) != enabled else { return }
        values[feature] = enabled
        defaults.set(enabled, forKey: Self.key(feature))
        if feature == .notifications { applyNotificationChoice() }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func applyNotificationChoice() {
        guard !isEnabled(.notifications) else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
#if canImport(UIKit)
        UIApplication.shared.unregisterForRemoteNotifications()
#endif
    }

    private static func key(_ feature: OiAppFeature) -> String { "oi.featureUsage.\(feature.rawValue)" }
}
