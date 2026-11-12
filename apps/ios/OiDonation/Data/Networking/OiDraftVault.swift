//
//  OiDraftVault.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import Foundation

struct OiLocalDraft: Codable, Identifiable, Equatable {
    var draft: OiStoryDraft
    var photos: [UUID] = []
    var uploadedPhotos: [UUID] = []
    var version = 0
    var submitted = false
    var creationStep: String?
    var customization: OiDraftCustomization?
    var removedMediaPaths: [String]?
    var removedPhotoIDs: Set<UUID>?
    /// Local consent selections, never inferred from visiting a screen or legacy drafts.
    var agreedConsentClauseIDs: Set<String>?
    var personalPlacement: OiPersonalPlacement?
    /// Preferred photo order by `OiEditingPhoto.orderKey`; nil keeps the attachment order.
    var photoOrder: [String]?
    var id: UUID { draft.id }
}

/// The last confirmed position on this account's device map, separate from edits and public review.
struct OiPersonalPlacement: Codable, Equatable {
    let regionID: String
    let name: String
    let latitude: Double
    let longitude: Double
    let heightMeters: Double
    let headingDegrees: Double
}

struct OiDraftListing {
    let drafts: [OiLocalDraft]
    let unreadableFiles: [String]
    let pendingDiscardCount: Int
}

private struct OiUnreadableDraftsError: LocalizedError {
    let count: Int
    var errorDescription: String? { "기기 초안 \(count)개를 읽지 못했습니다. 원본은 그대로 보관했습니다." }
}

struct OiDraftDiscardCleanupError: LocalizedError {
    var errorDescription: String? {
        "초안은 목록에서 제거했지만 첨부 파일 정리를 끝내지 못했어요. 버리기를 다시 시도해 주세요."
    }
}

struct OiEvidenceOperation: Codable, Equatable {
    var requestID: UUID
    var uploadID: UUID
    var contentType: String
    var fileExtension: String
    var previousStatus: String?
    var previousPath: String?
    var phase: String
    var failure: String?
    var storageOwnerID: UUID? = nil
    var operatorAIConsent: Bool? = nil

    func objectPath(owner: UUID) -> String {
        "\((storageOwnerID ?? owner).uuidString.lowercased())/\(requestID.uuidString.lowercased())/\(uploadID.uuidString.lowercased()).\(fileExtension)"
    }
}

actor OiDraftVault {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "oi-private-drafts", directoryHint: .isDirectory)
    }

    func purgeAccounts(_ owners: Set<UUID>) throws {
        let files = FileManager.default
        for owner in owners {
            let folder = directory.appending(path: owner.uuidString, directoryHint: .isDirectory)
            if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
        }
    }

    private func ownerDirectory(_ owner: UUID) throws -> URL {
        let url = directory.appending(path: owner.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
        return url
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic,.completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    func load(owner: UUID, id: UUID) throws -> OiLocalDraft? {
        let folder = try ownerDirectory(owner)
        guard !FileManager.default.fileExists(atPath: discardMarker(in: folder, id: id).path) else {
            throw OiDraftDiscardCleanupError()
        }
        let url = folder.appending(path: "draft-\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OiLocalDraft.self, from: Data(contentsOf: url))
    }

    @discardableResult
    func save(_ record: OiLocalDraft, owner: UUID) throws -> Bool {
        if let current = try load(owner: owner, id: record.id), current.version > record.version { return false }
        let url = try ownerDirectory(owner).appending(path: "draft-\(record.id.uuidString).json")
        try write(JSONEncoder().encode(record), to: url)
        return true
    }

    func list(owner: UUID) throws -> [OiLocalDraft] {
        let result = try listing(owner: owner)
        guard result.unreadableFiles.isEmpty else { throw OiUnreadableDraftsError(count: result.unreadableFiles.count) }
        return result.drafts
    }

    func listing(owner: UUID) throws -> OiDraftListing {
        let folder = try ownerDirectory(owner)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var drafts: [OiLocalDraft] = []
        var unreadableFiles: [String] = []
        var pendingDiscardCount = 0
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            if name.hasPrefix("discarded-draft-"), let id = UUID(uuidString: String(name.dropFirst("discarded-draft-".count))) {
                // A marker exists only after the user chose to discard this draft.
                do { try discard(owner: owner, id: id) }
                catch { pendingDiscardCount += 1 }
                continue
            }
            guard name.hasPrefix("draft-") else { continue }
            // File-system failures must remain visible; only decoding failures are isolated.
            let data = try Data(contentsOf: file)
            do { drafts.append(try JSONDecoder().decode(OiLocalDraft.self, from: data)) }
            catch is DecodingError { unreadableFiles.append(file.lastPathComponent) }
        }
        return OiDraftListing(drafts: drafts.sorted { $0.id.uuidString < $1.id.uuidString },
                              unreadableFiles: unreadableFiles.sorted(), pendingDiscardCount: pendingDiscardCount)
    }

    /// Copies account-scoped drafts after a verified server merge. Originals are never removed.
    func adoptDrafts(from owners: Set<UUID>, into target: UUID) throws -> Int {
        var unresolved = 0
        for owner in owners where owner != target {
            do {
                if var operation = try evidence(owner: owner), ["failed", "prepared", "uploading", "submitting"].contains(operation.phase) {
                    if let current = try evidence(owner: target) {
                        if current.uploadID != operation.uploadID { unresolved += 1 }
                    } else {
                        operation.storageOwnerID = operation.storageOwnerID ?? owner
                        let data = try attachment(owner: owner, id: operation.uploadID)
                        let destination = try ownerDirectory(target).appending(path: "attachment-\(operation.uploadID.uuidString)")
                        if FileManager.default.fileExists(atPath: destination.path), try Data(contentsOf: destination) != data {
                            throw OiServiceError.conflict
                        }
                        try saveAttachment(data, owner: target, id: operation.uploadID)
                        try saveEvidence(operation, owner: target)
                    }
                }
            } catch { unresolved += 1 }
            let sourceDirectory = try ownerDirectory(owner)
            let markerURL = sourceDirectory.appending(path: "adopted-drafts.json")
            var markers: [String: Int] = [:]
            if FileManager.default.fileExists(atPath: markerURL.path) {
                markers = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: markerURL))
            }
            let listing = try listing(owner: owner)
            unresolved += listing.unreadableFiles.count
            for record in listing.drafts {
                let marker = "\(target.uuidString)/\(record.id.uuidString)"
                if let adoptedVersion = markers[marker], adoptedVersion >= record.version { continue }
                do {
                    if let existing = try load(owner: target, id: record.id) {
                        if existing != record {
                            unresolved += 1; continue
                        }
                    } else {
                        var attachments: [(UUID, Data)] = []
                        for photoID in record.photos {
                            let data = try attachment(owner: owner, id: photoID)
                            let destination = try ownerDirectory(target).appending(path: "attachment-\(photoID.uuidString)")
                            if FileManager.default.fileExists(atPath: destination.path), try Data(contentsOf: destination) != data {
                                throw OiServiceError.conflict
                            }
                            attachments.append((photoID, data))
                        }
                        for (photoID, data) in attachments { try saveAttachment(data, owner: target, id: photoID) }
                        try save(record, owner: target)
                    }
                    markers[marker] = record.version
                    try write(JSONEncoder().encode(markers), to: markerURL)
                } catch { unresolved += 1 }
            }
        }
        return unresolved
    }

    func attachment(owner: UUID, id: UUID) throws -> Data {
        try Data(contentsOf: ownerDirectory(owner).appending(path: "attachment-\(id.uuidString)"))
    }

    func saveAttachment(_ data: Data, owner: UUID, id: UUID) throws {
        guard !data.isEmpty, data.count <= 10_485_760 else { throw OiServiceError.invalidInput }
        try write(data, to: ownerDirectory(owner).appending(path: "attachment-\(id.uuidString)"))
    }

    func discard(owner: UUID, id: UUID) throws {
        let folder = try ownerDirectory(owner)
        let files = FileManager.default
        let marker = discardMarker(in: folder, id: id)
        if !files.fileExists(atPath: marker.path) {
            guard let record = try load(owner: owner, id: id) else { return }
            guard record.id == id else { throw OiServiceError.invalidInput }
            let active = folder.appending(path: "draft-\(id.uuidString).json")
            // A same-directory rename hides the draft before removing any of its photos.
            try files.moveItem(at: active, to: marker)
        }
        do {
            let record = try JSONDecoder().decode(OiLocalDraft.self, from: Data(contentsOf: marker))
            guard record.id == id else { throw OiServiceError.invalidInput }
            for photoID in record.photos {
                let url = folder.appending(path: "attachment-\(photoID.uuidString)")
                if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
            }
            try files.removeItem(at: marker)
        } catch {
            throw OiDraftDiscardCleanupError()
        }
    }

    private func discardMarker(in folder: URL, id: UUID) -> URL {
        folder.appending(path: "discarded-draft-\(id.uuidString).json")
    }

    func schoolEvidenceReview(owner: UUID) throws -> OiSavedSchoolEvidenceReview? {
        let url = try ownerDirectory(owner).appending(path: "school-evidence-review.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OiSavedSchoolEvidenceReview.self, from: Data(contentsOf: url))
    }

    func saveSchoolEvidenceReview(_ review: OiSavedSchoolEvidenceReview, owner: UUID) throws {
        let url = try ownerDirectory(owner).appending(path: "school-evidence-review.json")
        try write(JSONEncoder().encode(review), to: url)
    }

    func evidence(owner: UUID) throws -> OiEvidenceOperation? {
        let url = try ownerDirectory(owner).appending(path: "evidence.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OiEvidenceOperation.self, from: Data(contentsOf: url))
    }

    func saveEvidence(_ operation: OiEvidenceOperation, owner: UUID) throws {
        try write(JSONEncoder().encode(operation), to: ownerDirectory(owner).appending(path: "evidence-\(operation.uploadID.uuidString).json"))
        try write(JSONEncoder().encode(operation), to: ownerDirectory(owner).appending(path: "evidence.json"))
    }
}

/// Local preview settings only. Not sent to the story API until the shared asset contract exists.
struct OiDraftCustomization: Codable, Equatable {
    enum Fill: String, Codable, CaseIterable { case solid, gradient }
    var fill: Fill = .solid
    var firstColor: UInt32 = 0xD3DBC4
    var secondColor: UInt32 = 0xF1F4EC
    var showsCharacter = true
    var garmentColors: [String: UInt32] = [:]
    /// Nil preserves the existing preset for older drafts. A look is local until the shared asset API exists.
    var wardrobe: OiWardrobeLook?
    var card: OiCardDesign?
    /// Local STEP 3 appearance. Older drafts use the default bare cucumber.
    var seedAppearance: OiSeedCucumberAppearance?
    var seedWhiteTshirt: Bool?
}

/// Card-space coordinates shared by the small editor frame and the final card.
/// Values are normalized, so changing device size cannot change the chosen crop.
struct OiCardPlacement: Codable, Equatable {
    var x = 0.5
    var y = 0.5
    var scale = 1.0
    var normalized: Self {
        Self(x: x.isFinite ? min(1.25, max(-0.25, x)) : 0.5,
             y: y.isFinite ? min(1.25, max(-0.25, y)) : 0.5,
             scale: scale.isFinite ? min(4, max(0.35, scale)) : 1)
    }
}

/// Radians around the portrait camera's target. This never changes the AR model.
struct OiCardOrientation: Codable, Equatable {
    var yaw = 0.0
    var pitch = 0.0
    var normalized: Self {
        let turn = yaw.isFinite ? yaw.remainder(dividingBy: 2 * .pi) : 0
        return Self(yaw: turn == 0 ? 0 : turn,
                    pitch: pitch.isFinite ? min(.pi / 3, max(-.pi / 3, pitch)) : 0)
    }
    func rotated(horizontal: Double, vertical: Double) -> Self {
        let current = normalized
        return Self(yaw: current.yaw - horizontal * 0.01,
                    pitch: current.pitch + vertical * 0.01).normalized
    }
    /// Cheap to compute on each gesture event; wardrobe/photo bytes are hashed separately.
    var cacheIdentity: String {
        let value = normalized
        return "\(value.yaw.bitPattern)-\(value.pitch.bitPattern)"
    }
}

/// Kept in the protected local draft, never added implicitly to the public API payload.
struct OiCardDesign: Codable, Equatable {
    var borderFill: OiDraftCustomization.Fill = .solid
    var borderFirst: UInt32 = 0xD9D9D9
    var borderSecond: UInt32 = 0xFFFFFF
    var pattern: Int? = nil
    var caption: String? = nil
    var anonymous = false
    var characterPlacement = OiCardPlacement()
    /// Optional so drafts saved before 3D rotation still decode at the front angle.
    var characterOrientation: OiCardOrientation? = nil
    var backgroundPlacement = OiCardPlacement()
    var backgroundPhoto: Data? = nil
    var portraitPNG: Data? = nil
    var portraitKey: String? = nil
}

enum OiDenim: String, CaseIterable, Codable, Identifiable {
    case lightBlue = "01-light-blue", classicBlue = "02-classic-blue", deepIndigo = "03-deep-indigo"
    case washedBlack = "04-washed-black", softGray = "05-soft-gray", ecru = "06-ecru"
    var id: String { rawValue }
    var resource: String { "oi-denim-" + rawValue }
    var title: String {
        switch self {
        case .lightBlue: "연청"; case .classicBlue: "중청"; case .deepIndigo: "진청"
        case .washedBlack: "흑청"; case .softGray: "그레이"; case .ecru: "에크루"
        }
    }
}

/// Stable item IDs; the renderer resolves a tested, source-matched assembly from these choices.
struct OiWardrobeLook: Codable, Equatable {
    enum Top: String, Codable, CaseIterable {
        case tshirt, hoodie, cardigan, postech
        var title: String {
            switch self { case .tshirt: "흰 반팔 티"; case .hoodie: "흰 후드티"; case .cardigan: "흰 가디건"; case .postech: "포스텍 과잠" }
        }
    }
    enum Bottom: String, Codable, CaseIterable {
        case long, shorts
        var title: String { self == .long ? "흰 긴바지" : "흰 반바지" }
    }
    enum Costume: String, Codable, CaseIterable, Identifiable {
        case dinosaur, raincoat, bee, cat
        case astronaut, scientist
        case catBear = "cat-bear", postechSelfie = "postech-selfie"
        case baseball, cowboy, farmer, sportswear
        case martialArts = "martial-arts"
        case schoolUniform = "school-uniform", schoolUniformTrousers = "school-uniform-trousers"
        case astronautNavy = "astronaut-navy", scientistGoggles = "scientist-goggles"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dinosaur: "공룡 잠옷"; case .raincoat: "노란 우비"
            case .bee: "꿀벌 의상"; case .cat: "고양이 잠옷"
            case .astronaut: "우주복"; case .scientist: "연구원"
            case .catBear: "곰돌이 고양이"; case .postechSelfie: "과잠 셀카"
            case .baseball: "야구복"; case .cowboy: "카우보이"; case .farmer: "농부"
            case .sportswear: "운동복"; case .martialArts: "도복"
            case .schoolUniform: "리본 교복"; case .schoolUniformTrousers: "바지 교복"
            case .astronautNavy: "남색 우주복"; case .scientistGoggles: "고글 연구원"
            }
        }
        var modelName: String { "wardrobe-costume-" + rawValue }
        var thumbnailName: String { "oi-costume-" + rawValue }
    }
    var costume: Costume?
    var top: Top = .tshirt
    var bottom: Bottom = .long
    var topColor: UInt32 = 0xFFFFFF
    var bottomColor: UInt32 = 0xFFFFFF
    var shoeColor: UInt32 = 0xFFFFFF
    var artwork = OiWardrobeArtwork()
    var fabrics: [String: OiDenim] = [:]

    var modelName: String { costume?.modelName ?? "wardrobe-\(top.rawValue)-\(bottom.rawValue)" }
    var bodySource: String { costume?.rawValue ?? (top == .tshirt ? (bottom == .shorts ? "shorts" : "base") : top.rawValue) }
    var title: String { costume?.title ?? "\(top.title) · \(bottom.title) · 흰 운동화" }

    init() {}
    private enum CodingKeys: String, CodingKey { case top, bottom, topColor, bottomColor, shoeColor, artwork, fabrics, costume }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        costume = try? values.decode(Costume.self, forKey: .costume)
        top = (try? values.decode(Top.self, forKey: .top)) ?? .tshirt
        bottom = (try? values.decode(Bottom.self, forKey: .bottom)) ?? .long
        topColor = ((try? values.decode(UInt32.self, forKey: .topColor)) ?? 0xFFFFFF) & 0xFFFFFF
        bottomColor = ((try? values.decode(UInt32.self, forKey: .bottomColor)) ?? 0xFFFFFF) & 0xFFFFFF
        shoeColor = ((try? values.decode(UInt32.self, forKey: .shoeColor)) ?? 0xFFFFFF) & 0xFFFFFF
        let savedFabrics = (try? values.decode([String: String].self, forKey: .fabrics)) ?? [:]
        fabrics = savedFabrics.filter { OiWardrobeArtwork.itemIDs.contains($0.key) }.compactMapValues(OiDenim.init(rawValue:))
        artwork = try values.decodeIfPresent(OiWardrobeArtwork.self, forKey: .artwork) ?? OiWardrobeArtwork()
    }
}


/// Normalized front/back placement; Foundation-only so local-draft recovery can be tested off-device.
enum OiPhotoSide: String, CaseIterable, Codable, Identifiable {
    case front, back
    var id: String { rawValue }
    var title: String { self == .front ? "앞면" : "뒷면" }
}
enum OiPhotoSlot: String, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
    var role: String { self == .top ? "Top" : "Bottom" }
    func itemID(in look: OiWardrobeLook) -> String {
        if let costume = look.costume { return "costume-" + costume.rawValue }
        return rawValue + "-" + (self == .top ? look.top.rawValue : look.bottom.rawValue)
    }
    func title(in look: OiWardrobeLook) -> String { look.costume?.title ?? (self == .top ? look.top.title : look.bottom.title) }
    func color(in look: OiWardrobeLook) -> UInt32 { self == .top ? look.topColor : look.bottomColor }
    func supports(_ look: OiWardrobeLook) -> Bool { look.costume == nil || self == .top }
    func preservesOriginalMaterial(in look: OiWardrobeLook) -> Bool { look.costume != nil || (self == .top && look.top == .postech) }
    func fabric(in look: OiWardrobeLook) -> OiDenim? { preservesOriginalMaterial(in: look) ? nil : look.fabrics[itemID(in: look)] }
    func resource(in look: OiWardrobeLook) -> String { "photo-" + look.modelName + "-" + rawValue }
}
struct OiPhotoPlacement: Codable, Equatable {
    var x = 0.5, y = 0.5, width = 0.55, rotation = 0.0
    var isValid: Bool {
        x.isFinite && y.isFinite && width.isFinite && rotation.isFinite &&
        (0...1).contains(x) && (0...1).contains(y) && (0.03...1.5).contains(width) && (-180...180).contains(rotation)
    }
}
struct OiPhotoLayer: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var source: String
    var side: OiPhotoSide = .front
    var placement = OiPhotoPlacement()
    var isValid: Bool { UUID(uuidString: id) != nil && placement.isValid && source.count == 64 && source.allSatisfy { "0123456789abcdef".contains($0) } }
}
enum OiPhotoEditingLimit {
    static let perSide = 2
    static func remaining(on side: OiPhotoSide, in layers: [OiPhotoLayer]) -> Int {
        max(0, min(perSide - layers.filter { $0.side == side }.count,
                   OiPhotoDesign.maximumLayers - layers.count))
    }
}

struct OiPhotoDesign: Codable, Equatable {
    static let maximumLayers = 8
    var version = UUID().uuidString
    // Missing in older drafts; their photos use the original, lower print frame.
    var frameRevision: Int? = 2
    var layers: [OiPhotoLayer] = []
    var isValid: Bool {
        UUID(uuidString: version) != nil && (1...2).contains(frameRevision ?? 1) && layers.count <= Self.maximumLayers &&
        Set(layers.map(\.id)).count == layers.count && layers.allSatisfy(\.isValid)
    }
}
/// Self-contained, deduplicated compressed photos live inside the account's protected draft.
/// No shared photo folder: deleting/adopting a draft cannot remove another user's artwork.
struct OiWardrobeArtwork: Codable, Equatable {
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumSourceBytes = 1024 * 1024
    static let itemIDs: Set<String> = Set(["top-tshirt", "top-hoodie", "top-cardigan", "top-postech", "bottom-long", "bottom-shorts"])
        .union(OiWardrobeLook.Costume.allCases.map { "costume-" + $0.rawValue })
    var designs: [String: OiPhotoDesign] = [:]
    var sources: [String: Data] = [:]
    var byteCount: Int { sources.values.reduce(0) { $0 + $1.count } }
    var isValid: Bool {
        let used = Set(designs.values.flatMap(\.layers).map(\.source))
        return Set(designs.keys).isSubset(of: Self.itemIDs) && designs.values.allSatisfy(\.isValid) &&
            Set(sources.keys) == used && byteCount <= Self.maximumBytes &&
            sources.values.allSatisfy { !$0.isEmpty && $0.count <= Self.maximumSourceBytes }
    }
    init() {}
    private enum CodingKeys: String, CodingKey { case designs, sources }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        designs = try values.decode([String: OiPhotoDesign].self, forKey: .designs)
        sources = try values.decode([String: Data].self, forKey: .sources)
        guard isValid else { throw DecodingError.dataCorruptedError(forKey: .designs, in: values, debugDescription: "Invalid local wardrobe artwork") }
    }
    mutating func set(_ design: OiPhotoDesign?, sources newSources: [String: Data] = [:], for item: String) throws {
        var next = self
        if let design, !design.layers.isEmpty { next.designs[item] = design } else { next.designs[item] = nil }
        next.sources.merge(newSources) { _, new in new }
        let used = Set(next.designs.values.flatMap(\.layers).map(\.source))
        next.sources = next.sources.filter { used.contains($0.key) }
        guard Self.itemIDs.contains(item), next.isValid else { throw OiPhotoDataError.limit }
        self = next
    }
}
enum OiPhotoDataError: LocalizedError {
    case limit, unreadable
    var errorDescription: String? {
        switch self {
        case .limit: "사진 용량이 너무 커요. 다른 사진을 선택하거나 사용하지 않는 디자인을 지워 주세요."
        case .unreadable: "사진을 불러오지 못했어요. 다른 사진으로 다시 시도해 주세요."
        }
    }
}
