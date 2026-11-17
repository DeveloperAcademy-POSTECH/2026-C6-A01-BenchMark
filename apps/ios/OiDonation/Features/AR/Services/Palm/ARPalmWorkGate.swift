//
//  ARPalmWorkGate.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//

import Foundation

/// One image in flight. Invalidating does not free its slot until the worker finishes.
nonisolated struct ARPalmWorkGate {
    struct Token: Equatable, Sendable { let generation: Int; let sequence: Int }
    private var generation = 0
    private var sequence = 0
    private var running: Token?
    private var lastSubmitted = -TimeInterval.infinity

    mutating func begin(at timestamp: TimeInterval, interval: TimeInterval) -> Token? {
        guard running == nil, timestamp.isFinite, timestamp >= 0, interval.isFinite, interval > 0,
              timestamp - lastSubmitted >= interval else { return nil }
        sequence += 1
        let token = Token(generation: generation, sequence: sequence)
        running = token
        lastSubmitted = timestamp
        return token
    }
    mutating func invalidate() { generation += 1; lastSubmitted = -.infinity }
    mutating func finish(_ token: Token) { if running == token { running = nil } }
    func accepts(_ token: Token) -> Bool { token.generation == generation && token.sequence == sequence }
}
