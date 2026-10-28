// Created by 이돈혁

import Foundation
import Darwin

nonisolated struct NFCWriteRequest: Sendable {
    let url: URL

    init(_ text: String) throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !value.isEmpty,
              !value.unicodeScalars.contains(where: { forbidden.contains($0) }),
              let url = URL(string: value, encodingInvalidCharacters: false),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              Self.hasValidHost(host, in: value),
              url.user == nil, url.password == nil,
              url.port.map({ (1...65535).contains($0) }) ?? true else {
            throw NFCWriteRequestError.invalidURL
        }
        self.url = url
    }

    private static func hasValidHost(_ host: String, in value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let hostRange = components.rangeOfHost else { return false }
        if value[hostRange].hasPrefix("[") {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
        }
        return true
    }
}

nonisolated enum NFCWriteRequestError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "공백이나 로그인 정보가 없는 올바른 HTTPS 호출 URL을 입력해 주세요."
    }
}
