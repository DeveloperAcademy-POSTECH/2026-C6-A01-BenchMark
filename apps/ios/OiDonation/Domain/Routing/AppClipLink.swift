//
//  AppClipLink.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/22/26.
//

import Foundation

enum AppClipLink {
    static let bundleIdentifier = "com.Spero.OiDonation.Clip"
    static let defaultURLString = "https://appclip.apple.com/id?p=\(bundleIdentifier)"

    static func storyID(in url: URL) -> String? {
        guard matches(url), let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "story" })?.value else { return nil }
        return UUID(uuidString: value)?.uuidString
    }

    static func storyURL(_ id: UUID) -> URL {
        var components = URLComponents(string: defaultURLString)!
        components.queryItems?.append(URLQueryItem(name: "story", value: id.uuidString.lowercased()))
        return components.url!
    }

    /// NFC tag ID for a scratch postcard (#291). The server links each tag to a published story,
    /// so a locked tag can be pointed at another story later.
    static func postcardID(in url: URL) -> String? {
        guard matches(url), let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "postcard" })?.value,
              isValidPostcardTag(value) else { return nil }
        return value
    }

    /// Same rule as `benchmark_private.oi_nfc_tags.tag_id`: lowercase letters, digits and hyphens, 1–40.
    static func isValidPostcardTag(_ value: String) -> Bool {
        (1...40).contains(value.count) && value.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLowercase || $0.isNumber)) }
    }

    static func postcardURL(_ id: String) -> URL {
        var components = URLComponents(string: defaultURLString)!
        components.queryItems?.append(URLQueryItem(name: "postcard", value: id))
        return components.url!
    }

    static func matches(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "appclip.apple.com",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.percentEncodedPath == "/id",
              components.fragment == nil else { return false }

        let identifiers = (components.queryItems ?? []).filter { $0.name == "p" }
        let stories = (components.queryItems ?? []).filter { $0.name == "story" }
        let postcards = (components.queryItems ?? []).filter { $0.name == "postcard" }
        guard stories.count <= 1, postcards.count <= 1 else { return false }
        if let story = stories.first, UUID(uuidString: story.value ?? "") == nil { return false }
        return identifiers.count == 1 && identifiers[0].value == bundleIdentifier
    }
}
