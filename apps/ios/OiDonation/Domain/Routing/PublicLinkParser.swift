import Foundation

/// Inject the team's approved domain; reject links from every other host.
struct PublicLinkParser {
    let allowedHost: String
    enum Destination: Hashable { case bench(String), story(String) }
    func parse(_ url: URL) -> Destination? {
        guard url.scheme == "https", url.host?.lowercased() == allowedHost.lowercased(),
              url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "benches": return .bench(parts[1])
        case "stories": return .story(parts[1])
        default: return nil
        }
    }
}

