//
//  OiBuildingNotesAPI.swift
//  OiDonation
//
//  Created by Codex on 11/16/26.
//

import Foundation

extension OiServiceAPI {
    private func noteRPC<T: Decodable>(_ name: String, payload: [String: Any], token: String? = nil, as: T.Type = T.self) async throws -> T {
        let data = try await request("rest/v1/rpc/" + name, method: "POST", token: token,
                                     body: JSONSerialization.data(withJSONObject: payload))
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func buildingNotes(building: String, before: CampusBuildingNote?) async throws -> [CampusBuildingNote] {
        var payload: [String: Any] = ["p_building": building]
        if let before { payload["p_before"] = before.createdAt; payload["p_before_id"] = before.id.uuidString }
        return try await noteRPC("oi_building_notes", payload: payload)
    }

    func postBuildingNote(id: UUID, building: String, body: String, token: String) async throws -> CampusBuildingNote {
        try await noteRPC("oi_post_building_note", payload: ["p_id": id.uuidString, "p_building": building, "p_body": body], token: token)
    }

    func deleteBuildingNote(id: UUID, token: String) async throws {
        let receipt: OiContentReportReceipt = try await noteRPC("oi_delete_building_note", payload: ["p_id": id.uuidString], token: token)
        guard receipt.id == id, receipt.status == "deleted" else { throw OiServiceError.conflict }
    }

    func reportBuildingNote(id: UUID, reason: String, detail: String, token: String) async throws -> OiContentReportReceipt {
        let receipt: OiContentReportReceipt = try await noteRPC("oi_report_building_note",
            payload: ["p_note": id.uuidString, "p_reason": reason, "p_detail": detail], token: token)
        guard ["pending", "dismissed", "deleted"].contains(receipt.status) else { throw OiServiceError.conflict }
        return receipt
    }

    func buildingNoteReports(offset: Int, token: String) async throws -> [CampusBuildingNoteReport] {
        try await noteRPC("oi_building_note_reports", payload: ["p_offset": offset], token: token)
    }

    func reviewBuildingNote(report: UUID, action: String, note: String, token: String) async throws {
        let receipt: OiContentReportReceipt = try await noteRPC("oi_review_building_note",
            payload: ["p_report": report.uuidString, "p_action": action, "p_note": note], token: token)
        guard receipt.id == report, receipt.status == action else { throw OiServiceError.conflict }
    }
}
