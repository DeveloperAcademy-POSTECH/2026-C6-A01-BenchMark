//
//  OiPickleCoins.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import Foundation

extension OiServiceAPI {
    private func coinDecode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    func pickleWallet(token: String) async throws -> OiPickleWallet {
        let data = try await request("rest/v1/rpc/oi_pickle_wallet", method: "POST", token: token, body: Data("{}".utf8))
        let wallet = try coinDecode(OiPickleWallet.self, from: data)
        guard wallet.isValid else { throw OiPickleCoinError.unavailable }
        return wallet
    }

    func purchaseFarmerItem(_ item: String, operation: UUID, token: String) async throws -> OiFarmerPurchaseReceipt {
        let body = try JSONSerialization.data(withJSONObject: ["p_item": item, "p_operation": operation.uuidString])
        let data = try await request("rest/v1/rpc/oi_purchase_farmer_item", method: "POST", token: token, body: body)
        let receipt = try coinDecode(OiFarmerPurchaseReceipt.self, from: data)
        guard receipt.item == item, receipt.wallet.isValid, receipt.wallet.ownedItems.contains(item) else {
            throw OiPickleCoinError.unavailable
        }
        return receipt
    }

    func startCoinEvidence(_ id: UUID, token: String) async throws -> OiCoinEvidence {
        let data = try await request("rest/v1/rpc/oi_start_coin_evidence", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["p_id": id.uuidString]))
        return try coinDecode(OiCoinEvidence.self, from: data)
    }

    func submitCoinEvidence(_ id: UUID, path: String, token: String) async throws -> OiCoinEvidence {
        let data = try await request("rest/v1/rpc/oi_submit_coin_evidence", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["p_id": id.uuidString, "p_object_path": path, "p_consent_version": 1]))
        return try coinDecode(OiCoinEvidence.self, from: data)
    }

    func cancelCoinEvidence(_ id: UUID, token: String) async throws -> OiCoinEvidenceCancellation {
        let data = try await request("rest/v1/rpc/oi_cancel_coin_evidence", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["p_id": id.uuidString]))
        let receipt = try coinDecode(OiCoinEvidenceCancellation.self, from: data)
        guard receipt.request.id == id, receipt.request.coinVerification == true,
              receipt.wallet.isValid, !receipt.credited,
              !["draft", "pending"].contains(receipt.request.status) else { throw OiPickleCoinError.unavailable }
        return receipt
    }

    func analyzeCoinEvidence(_ id: UUID, token: String) async throws -> OiCoinEvidenceReceipt {
        let data = try await request("functions/v1/analyze-donation-evidence", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["evidence_id": id.uuidString]), timeout: 100)
        let receipt = try coinDecode(OiCoinEvidenceReceipt.self, from: data)
        guard receipt.request.id == id, receipt.wallet.isValid,
              receipt.reviewType == "pickle_coin_certificate", !receipt.authenticityVerified, !receipt.holderVerified else {
            throw OiPickleCoinError.unavailable
        }
        return receipt
    }
}
