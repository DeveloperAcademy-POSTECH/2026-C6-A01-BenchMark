import Foundation
import Observation
import Security

/// No approval or real story is inferred from local demo placements.
@MainActor @Observable
final class CampusSharedStore {
    private(set) var items: [CampusSharedOi] = []
    private(set) var mine: [CampusSharedOi] = []
    private(set) var refreshing = false
    private(set) var credential: CampusWriterCredential?
    var error: String?
    var notice: String?
    let api: CampusSharedAPI
    private var generation = 0
    var configured: Bool { api.origin != nil }
    var authorized: Bool { credential?.isValid == true }

    init(api: CampusSharedAPI? = nil) {
        let api = api ?? CampusSharedAPI()
        self.api = api
        if let host = api.origin?.absoluteString,
           let data = try? CampusWriterKeychain.read(host),
           let value = try? JSONDecoder().decode(CampusWriterCredential.self, from: data), value.isValid {
            credential = value
        }
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true; error = nil
        let current = generation
        defer { refreshing = false }
        do {
            let values = try await api.list()
            try Task.checkCancellation()
            guard current == generation else { return }
            items = values
            if authorized, let credential {
                do {
                    let ownItems = try await api.list(mine: true, token: credential.token)
                    if current == generation { mine = ownItems }
                } catch {
                    if current == generation { handle(error); mine = [] }
                }
            } else { mine = [] }
        } catch is CancellationError { }
        catch { if current == generation { items = []; handle(error) } }
    }
    func register(code: String) async throws {
        let value = try await api.redeem(code.trimmingCharacters(in: .whitespacesAndNewlines))
        guard value.isValid, let host = api.origin?.absoluteString else { throw CampusSharedError.invalidResponse }
        try CampusWriterKeychain.save(JSONEncoder().encode(value), host: host)
        generation += 1
        credential = value
        await refresh()
    }
    func story(_ id: UUID, publicOnly: Bool = false) async throws -> CampusSharedOi {
        let token = publicOnly ? nil : credential?.token
        do { return try await api.story(id, token: token) }
        catch CampusSharedError.unauthorized {
            if token == credential?.token { forgetCredential() }
            return try await api.story(id)
        }
    }
    func save(_ draft: CampusSharedDraft) async throws {
        guard authorized, let credential else { throw CampusSharedError.unauthorized }
        do { try await api.save(draft, token: credential.token) }
        catch { if credential.token == self.credential?.token { handle(error) }; throw error }
        notice = "저장됐어요. 운영진의 공개 검토 후 다른 이용자에게 표시됩니다."
        await refresh()
    }
    func remove(_ item: CampusSharedOi) async throws {
        guard authorized, let credential else { throw CampusSharedError.unauthorized }
        do { try await api.remove(item, token: credential.token) }
        catch { if credential.token == self.credential?.token { handle(error) }; throw error }
        await refresh()
    }
    func forgetCredential() {
        generation += 1
        if let host = api.origin?.absoluteString { CampusWriterKeychain.remove(host) }
        credential = nil; mine = []
    }
    private func handle(_ error: Error) {
        if case CampusSharedError.unauthorized = error { forgetCredential() }
        self.error = error.localizedDescription
    }
}

private enum CampusWriterKeychain {
    static func query(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "OiDonation.CampusWriter", kSecAttrAccount as String: host]
    }
    static func read(_ host: String) throws -> Data? {
        var request = query(host); request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CampusSharedError.keychain }
        return value as? Data
    }
    static func save(_ data: Data, host: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query(host) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(host).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CampusSharedError.keychain }
    }
    static func remove(_ host: String) { SecItemDelete(query(host) as CFDictionary) }
}
