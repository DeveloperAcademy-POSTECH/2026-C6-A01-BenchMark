//
//  OiSchoolEvidenceContractTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 11/5/26.
//

import XCTest
@testable import OiDonation

@MainActor
final class OiSchoolEvidenceContractTests: XCTestCase {
    func testReviewUsesExplicitDocumentRequestAndRejectsVerifiedClaims() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let previous = OiStoreURLProtocol.handle
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let document = Data("%PDF-synthetic-document".utf8)
        let base: [String: Any] = [
            "review_type": "school_affiliation", "human_review_required": true,
            "affiliation_verified": false, "authenticity_verified": false,
            "summary": ["outcome": "manual_review", "title": "추가 확인 필요", "detail": "가상 자료",
                        "next_step": "자료를 확인해 주세요."]
        ]
        for field in ["valid", "human_review_required", "affiliation_verified", "authenticity_verified"] {
            var response = base
            if field != "valid" { response[field] = field != "human_review_required" }
            let bytes = try JSONSerialization.data(withJSONObject: response)
            OiStoreURLProtocol.handle = { request, client in
                XCTAssertEqual(request.url?.path, "/functions/v1/analyze-school-evidence")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/pdf")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
                XCTAssertEqual(request.timeoutInterval, 70)
                XCTAssertEqual(OiTestBackend.body(request), document)
                client.respond(200, bytes)
            }
            do {
                let review = try await api.reviewSchoolEvidence(document, contentType: "application/pdf", token: "synthetic-token")
                XCTAssertEqual(field, "valid", "A review must never certify identity, authenticity, or affiliation")
                XCTAssertEqual(review.summary?.outcome, "manual_review")
            } catch {
                XCTAssertNotEqual(field, "valid", "The supported review contract must decode")
            }
        }
    }

    func testSchoolProfileRPCSeparatesPrivateMetadataFromPublicDonorFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let previous = OiStoreURLProtocol.handle
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let owner = UUID()
        let response: [String: Any] = [
            "id": owner.uuidString, "nickname": "Legacy nickname", "farmer_asset": "OiFarmer", "farm_name": "오이",
            "school_id": "postech", "public_name": "Public donor", "admission_year": "26", "department": "Public department",
            "school_admission_year": 2020, "school_department": "Private department"
        ]
        let bytes = try JSONSerialization.data(withJSONObject: response)
        OiStoreURLProtocol.handle = { request, client in
            XCTAssertEqual(request.httpMethod, "POST")
            if request.url?.path == "/rest/v1/rpc/oi_update_school_profile" {
                let payload = try? JSONSerialization.jsonObject(with: OiTestBackend.body(request)) as? [String: Any]
                XCTAssertEqual(payload?.keys.sorted(), ["p_admission_year", "p_department", "p_school_id"])
                XCTAssertEqual(payload?["p_admission_year"] as? Int, 2020)
                XCTAssertEqual(payload?["p_department"] as? String, "Private department")
            } else {
                XCTAssertEqual(request.url?.path, "/rest/v1/rpc/oi_school_profile")
            }
            client.respond(200, bytes)
        }
        let read = try await api.schoolProfile(owner: owner, token: "synthetic-token")
        let saved = try await api.updateSchoolProfile(owner: owner, schoolID: "postech", admissionYear: 2020,
            department: "Private department", token: "synthetic-token")
        XCTAssertEqual(read, saved)
        XCTAssertEqual(saved.admissionYear, "26")
        XCTAssertEqual(saved.department, "Public department")
        XCTAssertEqual(saved.schoolAdmissionYear, 2020)
        XCTAssertEqual(saved.schoolDepartment, "Private department")
        XCTAssertEqual(saved.farmName, "오이")

        var missingPrivateReceipt = response
        missingPrivateReceipt.removeValue(forKey: "school_admission_year")
        missingPrivateReceipt.removeValue(forKey: "school_department")
        let missingPrivateBytes = try JSONSerialization.data(withJSONObject: missingPrivateReceipt)
        OiStoreURLProtocol.handle = { _, client in client.respond(200, missingPrivateBytes) }
        do {
            _ = try await api.updateSchoolProfile(owner: owner, schoolID: "postech", admissionYear: 2020,
                department: "Private department", token: "synthetic-token")
            XCTFail("A public academic profile must never confirm a private school update")
        } catch OiServiceError.unavailable {
            // Public fields cannot satisfy the required private write receipt.
        } catch {
            XCTFail("Unexpected school profile error: \(error)")
        }
    }

    func testSavedSummaryRestoresOnlyForItsOwner() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SchoolSummary-\(UUID())")
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
        }
        let owner = UUID(), other = UUID()
        let summary = OiSchoolEvidenceReview.Summary(outcome: "manual_review", title: "추가 확인 필요",
            detail: "가상 자료", nextStep: "확인해 주세요.", reference: nil)
        let saved = OiSavedSchoolEvidenceReview(summary: summary, reviewedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try await OiDraftVault(directory: directory).saveSchoolEvidenceReview(saved, owner: owner)
        let restored = try await OiDraftVault(directory: directory).schoolEvidenceReview(owner: owner)
        let unrelated = try await OiDraftVault(directory: directory).schoolEvidenceReview(owner: other)
        XCTAssertEqual(restored?.summary.title, saved.summary.title)
        XCTAssertEqual(restored?.reviewedAt, saved.reviewedAt)
        XCTAssertNil(unrelated)
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.filter { $0.hasSuffix(".json") }.count, 1, "The vault saves only the summary receipt")
    }
}
