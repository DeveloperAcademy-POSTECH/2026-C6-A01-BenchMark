//
//  ContentSafetyChecks.swift
//  OiDonationChecks
//
//  Created by 이돈혁 on 11/6/26.
//

import Foundation

@main struct ContentSafetyChecks {
    @MainActor static func main() throws {
        let suite = "OiContentSafetyChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = OiContentSafetyStore(defaults: defaults)
        let second = OiContentSafetyStore(defaults: defaults)
        let a = UUID(), b = UUID()
        precondition(first.setBlocked(a, name: "첫 작성자", blocked: true))
        precondition(second.setBlocked(b, name: "다른 작성자", blocked: true))
        first.reload()
        precondition(first.isBlocked(a) && first.isBlocked(b), "Other surface's changes must survive")
        let reopened = OiContentSafetyStore(defaults: defaults)
        precondition(reopened.isBlocked(a) && reopened.isBlocked(b), "Blocks survive app relaunch")
        precondition(second.setBlocked(a, name: "", blocked: false))
        first.reload()
        precondition(!first.isBlocked(a) && first.isBlocked(b), "Unblocking preserves unrelated blocks")
        let valid = defaults.data(forKey: "oi.blockedAuthors.v1")!
        let corrupt = Data("broken".utf8)
        defaults.set(corrupt, forKey: "oi.blockedAuthors.v1")
        first.reload()
        precondition(first.error != nil && first.isBlocked(b), "Read failure preserves loaded block state")
        precondition(!first.setBlocked(a, name: "실패", blocked: true))
        precondition(defaults.data(forKey: "oi.blockedAuthors.v1") == corrupt, "Never overwrite unreadable storage")
        defaults.set(valid, forKey: "oi.blockedAuthors.v1")
        first.reload()
        precondition(first.error == nil && first.isBlocked(b))
        let unavailable = OiContentSafetyStore(defaults: nil)
        precondition(!unavailable.setBlocked(a, name: "실패", blocked: true))
        print("PASS: block persistence, cross-surface reload, unblock, corruption preservation and recovery")
    }
}
