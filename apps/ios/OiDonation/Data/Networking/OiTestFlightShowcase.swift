//
//  OiTestFlightShowcase.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import Foundation
import StoreKit

/// Temporary publication exception for the November 20 showcase. Remove after the event.
nonisolated enum OiTestFlightShowcase {
    static var transactionProvider: (() async throws -> String)? {
        #if DEBUG || targetEnvironment(simulator)
        return nil
        #else
        return {
            let result = try await AppTransaction.shared
            guard case .verified(let transaction) = result, transaction.environment == .sandbox else {
                throw OiServiceError.unavailable
            }
            return result.jwsRepresentation
        }
        #endif
    }
}
