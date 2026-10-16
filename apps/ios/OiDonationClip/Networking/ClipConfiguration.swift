import Foundation

nonisolated struct ClipConfiguration: Sendable {
    let publicHost: String
    let apiBase: URL
    let assetHosts: Set<String>
    var allowsLocalHTTP = false

    static func configured(bundle: Bundle = .main) throws -> Self {
        func value(_ key: String) -> String {
#if DEBUG
            if let value = ProcessInfo.processInfo.environment[key] { return value }
#endif
            return bundle.object(forInfoDictionaryKey: key) as? String ?? ""
        }
        let host = value("OI_CLIP_PUBLIC_HOST").lowercased()
        guard !host.isEmpty, host != "unconfigured.invalid", !host.contains("/"),
              let api = URL(string: value("OI_CLIP_API_BASE_URL")), api.host != nil else {
            throw ClipError.configuration
        }
        let hosts = Set(value("OI_CLIP_ASSET_HOSTS").split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })
        var config = Self(publicHost: host, apiBase: api, assetHosts: hosts)
#if DEBUG
        config.allowsLocalHTTP = value("OI_CLIP_ALLOW_LOCALHOST") == "1"
#endif
        guard config.permits(api, hosts: Set([api.host!.lowercased()])), !hosts.isEmpty,
              api.query == nil, api.fragment == nil else { throw ClipError.configuration }
        return config
    }

    func permits(_ url: URL, hosts: Set<String>) -> Bool {
        guard let host = url.host?.lowercased(), hosts.contains(host),
              url.user == nil, url.password == nil, url.fragment == nil else { return false }
        if url.scheme == "https" { return url.port == nil || url.port == 443 }
#if DEBUG
        return allowsLocalHTTP && url.scheme == "http" && ["127.0.0.1", "localhost"].contains(host)
#else
        return false
#endif
    }
}

nonisolated enum ClipError: LocalizedError {
    case configuration, invalidLink, unavailable, invalidResponse, tooLarge, integrity, assetURL
    var errorDescription: String? {
        switch self {
        case .configuration: "서비스 연결 주소가 아직 설정되지 않았어요. 운영 도메인과 API·콘텐츠 주소를 설정해 주세요."
        case .invalidLink: "올바른 벤치 링크가 아니에요. 명패의 NFC를 다시 인식해 주세요."
        case .unavailable: "이 벤치에서 공개된 이야기를 찾을 수 없어요."
        case .invalidResponse: "콘텐츠를 불러오지 못했어요. 연결을 확인하고 다시 시도해 주세요."
        case .tooLarge: "콘텐츠가 허용 용량보다 커서 불러올 수 없어요."
        case .integrity: "캐릭터 파일을 확인하지 못했어요. 다시 시도해 주세요."
        case .assetURL: "허용되지 않은 콘텐츠 주소예요."
        }
    }
}

nonisolated enum ClipRoute: Equatable, Sendable {
    case bench(String), story(String)
    var id: String { switch self { case .bench(let id), .story(let id): id } }
    static func parse(_ url: URL, host: String) throws -> Self {
        guard url.scheme == "https", url.host?.lowercased() == host.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              url.query == nil, url.fragment == nil else { throw ClipError.invalidLink }
        let parts = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "").components(separatedBy: "/")
        guard parts.count == 3, parts[0].isEmpty, validID(parts[2]) else { throw ClipError.invalidLink }
        switch parts[1] {
        case "benches": return .bench(parts[2])
        case "stories": return .story(parts[2])
        default: throw ClipError.invalidLink
        }
    }
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 80 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
