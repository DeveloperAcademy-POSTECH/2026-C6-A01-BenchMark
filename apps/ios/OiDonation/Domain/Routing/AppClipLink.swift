// Created by 이돈혁

import Foundation

enum AppClipLink {
    static let bundleIdentifier = "com.Spero.OiDonation.Clip"
    static let defaultURLString = "https://appclip.apple.com/id?p=\(bundleIdentifier)"

    static func matches(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "appclip.apple.com",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.percentEncodedPath == "/id",
              components.fragment == nil else { return false }

        let identifiers = (components.queryItems ?? []).filter { $0.name == "p" }
        return identifiers.count == 1 && identifiers[0].value == bundleIdentifier
    }
}
