//
//  OiAccountConnectionFlow.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import Foundation

enum OiAccountConnectionMode: Equatable { case addLoginMethod, mergeExisting }

/// Owns only in-memory authentication proofs and the shared connection route.
struct OiAccountConnectionFlow {
    enum Representative: Hashable { case current, additional }

    let entryMode: OiAccountConnectionMode
    private(set) var mode: OiAccountConnectionMode
    private(set) var currentProof: OiSession?
    private(set) var additionalProof: OiSession?
    private(set) var representative: Representative = .current
    private(set) var operationID = UUID()
    private var additionalIsNew: Bool?

    init(mode: OiAccountConnectionMode = .mergeExisting) {
        entryMode = mode
        self.mode = mode
    }

    var canChooseRepresentative: Bool { mode == .mergeExisting && additionalIsNew == false }
    var hasClassifiedAdditional: Bool { additionalIsNew != nil }
    var pair: (target: OiSession, source: OiSession)? {
        guard let currentProof, let additionalProof else { return nil }
        return representative == .current ? (currentProof, additionalProof) : (additionalProof, currentProof)
    }

    mutating func acceptCurrentProof(_ proof: OiSession) {
        currentProof = proof
        if let additionalProof, additionalProof.user.id != proof.user.id {
            // The caller has revalidated the same canonical current account.
            // Refreshing its proof must not require authenticating the source again.
            resetOperation()
        } else {
            additionalProof = nil
            resetAdditionalRoute()
        }
    }

    mutating func acceptAdditionalProof(_ proof: OiSession) {
        additionalProof = proof
        resetAdditionalRoute()
    }

    mutating func resolvePreview(sourceIsNew: Bool) {
        guard currentProof != nil, additionalProof != nil else { return }
        // Once a separate existing account is found, reversing the representative
        // must not reinterpret a blank current account as a new login method.
        if additionalIsNew == nil || (representative == .current && additionalIsNew == true) {
            additionalIsNew = sourceIsNew
            mode = sourceIsNew ? .addLoginMethod : .mergeExisting
        }
    }

    @discardableResult
    mutating func chooseRepresentative(_ choice: Representative) -> Bool {
        guard canChooseRepresentative, choice != representative else { return false }
        representative = choice
        resetOperation()
        return true
    }

    mutating func resetOperation() { operationID = UUID() }

    mutating func reviewChanged() {
        if additionalIsNew == true { additionalIsNew = nil }
        resetOperation()
    }

    mutating func clearProofs() {
        currentProof = nil
        additionalProof = nil
        resetAdditionalRoute()
    }

    private mutating func resetAdditionalRoute() {
        representative = .current
        additionalIsNew = nil
        mode = entryMode
        resetOperation()
    }
}
