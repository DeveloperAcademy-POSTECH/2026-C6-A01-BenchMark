//
//  OiContentSafetyStore.swift
//  OiDonation / OiDonationClip
//
//  Created by 이돈혁 on 11/6/26.
//

import Foundation
import Observation

@MainActor @Observable
final class OiContentSafetyStore {
    static let shared = OiContentSafetyStore()
    private static let key = "oi.blockedAuthors.v1"
    private let defaults: UserDefaults?
    private(set) var authors: [String: String] = [:]
    private(set) var error: String?

    init(defaults: UserDefaults? = UserDefaults(suiteName: "group.com.Spero.OiDonation")) {
        self.defaults = defaults
        reload()
    }

    func isBlocked(_ id: UUID) -> Bool { authors[id.uuidString.lowercased()] != nil }

    func reload() {
        guard let defaults else { error = "기기의 차단 기록을 열 수 없어요."; return }
        do {
            let loaded = try defaults.data(forKey: Self.key).map { try JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            guard loaded.keys.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw CocoaError(.fileReadCorruptFile) }
            authors = loaded; error = nil
        } catch { self.error = "차단 기록을 읽지 못했어요. 기존 기록은 보존했어요. 다시 시도해 주세요." }
    }

    @discardableResult
    func setBlocked(_ id: UUID, name: String, blocked: Bool) -> Bool {
        reload()
        guard error == nil, let defaults else { return false }
        var updated = authors
        updated[id.uuidString.lowercased()] = blocked ? String(name.prefix(100)) : nil
        do {
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: Self.key)
            guard defaults.data(forKey: Self.key) == data else { throw CocoaError(.fileWriteUnknown) }
            authors = updated
            return true
        } catch { self.error = "차단 기록을 저장하지 못했어요. 다시 시도해 주세요."; return false }
    }
}
