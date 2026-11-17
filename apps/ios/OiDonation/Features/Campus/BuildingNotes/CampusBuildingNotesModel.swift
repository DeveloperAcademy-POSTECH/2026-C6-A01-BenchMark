//
//  CampusBuildingNotesModel.swift
//  OiDonation
//
//  Created by Codex on 11/16/26.
//

import Foundation
import Observation

struct CampusBuildingNote: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let buildingId: String
    let authorId: UUID
    let body: String
    let createdAt: String
    let nickname: String
    let admissionYear: String?
    let department: String?

    var authorLabel: String {
        // These are deliberately public profile fields, never school-evidence metadata.
        let year = admissionYear?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let department = department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let academic = [year.isEmpty ? "" : String(year.suffix(2)) + "학번", department].filter { !$0.isEmpty }.joined(separator: " ")
        return academic.isEmpty ? nickname : academic
    }
}

struct CampusBuildingNoteReport: Decodable, Identifiable {
    let id: UUID
    let noteId: UUID
    let buildingName: String
    let body: String
    let reason: String
    let detail: String
    let status: String
    let noteStatus: String
    let reviewNote: String?
}

@MainActor protocol CampusBuildingNoteServing: AnyObject {
    var buildingNoteAccountID: UUID? { get }
    var canWriteBuildingNote: Bool { get }
    func buildingNotes(building: String, before: CampusBuildingNote?) async throws -> [CampusBuildingNote]
    func prepareBuildingNote(id: UUID, building: String, body: String, owner: UUID) async throws -> UUID
    func postBuildingNote(id: UUID, building: String, body: String) async throws -> CampusBuildingNote
    func deleteBuildingNote(id: UUID) async throws
}

extension CampusBuildingNoteServing {
    func prepareBuildingNote(id: UUID, building: String, body: String, owner: UUID) async throws -> UUID { id }
}

@MainActor @Observable final class CampusBuildingNotesModel {
    static let textLimit = 140
    let buildingID: String
    private let service: any CampusBuildingNoteServing
    private(set) var notes: [CampusBuildingNote] = []
    private(set) var loading = false
    private(set) var sending = false
    private(set) var hasLoaded = false
    private(set) var hasMore = false
    private(set) var hasLoadedOlderNotes = false
    private(set) var error: String?
    private(set) var failedSend = false
    private(set) var sentID: UUID?
    var text = ""
    private var generation = UUID()
    private var contentRevision = 0
    private var owner: UUID?
    private var pending: (id: UUID, body: String)?
    private var cursor: CampusBuildingNote?

    init(buildingID: String, service: any CampusBuildingNoteServing) {
        self.buildingID = buildingID; self.service = service
        owner = service.buildingNoteAccountID
    }

    var cleanedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping }
    var textCount: Int { cleanedText.unicodeScalars.count }
    var canSend: Bool { service.canWriteBuildingNote && !sending && (1...Self.textLimit).contains(textCount) }

    func invalidate() {
        generation = UUID(); loading = false; sending = false
    }

    func resetForAccount() {
        invalidate()
        if owner != service.buildingNoteAccountID {
            text = ""; pending = nil; sentID = nil; notes = []; cursor = nil; hasLoaded = false; hasMore = false
            hasLoadedOlderNotes = false
            failedSend = false; error = nil
        }
        owner = service.buildingNoteAccountID
    }

    func load(older: Bool = false) async {
        guard !loading, !older || hasMore else { return }
        let request = generation, account = service.buildingNoteAccountID, revision = contentRevision
        loading = true
        if !failedSend { error = nil }
        defer { if request == generation { loading = false } }
        do {
            let page = try await service.buildingNotes(building: buildingID, before: older ? cursor : nil)
            guard request == generation, account == service.buildingNoteAccountID, !Task.isCancelled else { return }
            guard revision == contentRevision else { return }
            // Keep the server page's cursor even when local author blocking hides every row.
            cursor = page.last; hasMore = page.count == 50
            hasLoadedOlderNotes = older
            var unique = Dictionary(uniqueKeysWithValues: (older ? notes : []).map { ($0.id, $0) })
            for item in page where item.buildingId == buildingID { unique[item.id] = item }
            notes = unique.values.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
            hasLoaded = true
        } catch {
            guard request == generation, account == service.buildingNoteAccountID, !OiServiceFailure.isCancellation(error) else { return }
            self.error = error.localizedDescription
        }
    }

    func send() async {
        guard canSend, let account = service.buildingNoteAccountID else { return }
        let request = generation, body = cleanedText
        // An uncertain network result reuses the same UUID; it cannot create two notes.
        if pending?.body != body { pending = (UUID(), body) }
        guard let pending else { return }
        sending = true; error = nil; failedSend = false
        defer { if request == generation { sending = false } }
        do {
            let id = try await service.prepareBuildingNote(id: pending.id, building: buildingID, body: body, owner: account)
            guard request == generation, account == service.buildingNoteAccountID, !Task.isCancelled else { return }
            self.pending = (id, body)
            let receipt = try await service.postBuildingNote(id: id, building: buildingID, body: body)
            guard request == generation, account == service.buildingNoteAccountID,
                  self.pending?.id == id, !Task.isCancelled else { return }
            guard receipt.id == id, receipt.authorId == account,
                  receipt.buildingId == buildingID, receipt.body == body else { throw OiServiceError.conflict }
            contentRevision += 1
            notes.removeAll { $0.id == receipt.id }; notes.append(receipt)
            if cleanedText == body { text = "" }
            self.pending = nil; sentID = receipt.id
        } catch {
            guard request == generation, account == service.buildingNoteAccountID,
                  !OiServiceFailure.isCancellation(error) else { return }
            failedSend = true
            self.error = error.localizedDescription
        }
    }

    func delete(_ note: CampusBuildingNote) async {
        guard note.authorId == service.buildingNoteAccountID else { return }
        let request = generation, account = service.buildingNoteAccountID
        do {
            try await service.deleteBuildingNote(id: note.id)
            guard request == generation, account == service.buildingNoteAccountID, !Task.isCancelled else { return }
            contentRevision += 1
            notes.removeAll { $0.id == note.id }
            if pending?.id == note.id { pending = nil }
        } catch {
            guard request == generation, account == service.buildingNoteAccountID, !OiServiceFailure.isCancellation(error) else { return }
            self.error = error.localizedDescription
        }
    }
}
