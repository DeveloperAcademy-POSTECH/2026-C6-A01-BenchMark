//
//  ARPalmChecks.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//

import Foundation
import CoreGraphics
import simd

@main struct ARPalmChecks {
    static func main() throws {
        func expect(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "ARPalmChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var gate = ARPalmWorkGate()
        let first = gate.begin(at: 1, interval: 0.1)!
        try expect(gate.begin(at: 2, interval: 0.1) == nil, "Never queue a second image")
        gate.invalidate()
        try expect(!gate.accepts(first), "Pause invalidates the pending result")
        try expect(gate.begin(at: 3, interval: 0.1) == nil, "Invalidation keeps the in-flight slot occupied")
        gate.finish(first)
        let second = gate.begin(at: 3, interval: 0.1)!
        gate.finish(first)
        try expect(gate.begin(at: 4, interval: 0.1) == nil, "An old completion cannot release a newer job")
        gate.finish(second)
        try expect(gate.begin(at: 3.05, interval: 0.1) == nil, "Inference is rate limited")
        let third = gate.begin(at: 3.11, interval: 0.1)!
        try expect(!gate.accepts(second) && gate.accepts(third), "Late callbacks lose to newer submitted images")
        gate.finish(third)
        try expect(gate.begin(at: .nan, interval: 0.1) == nil, "Reject invalid timestamps")

        let sensor = CGPoint(x: 0.3, y: 0.7)
        let display = CGAffineTransform(a: 1.2, b: 0, c: 0, d: 1, tx: -0.1, ty: 0)
        let expected = sensor.applying(display)
        for turns in 0...3 {
            let p: CGPoint
            switch turns {
            case 1: p = CGPoint(x: 1 - sensor.y, y: sensor.x)
            case 2: p = CGPoint(x: 1 - sensor.x, y: 1 - sensor.y)
            case 3: p = CGPoint(x: sensor.y, y: 1 - sensor.x)
            default: p = sensor
            }
            let mapped = ARPalmGeometry.viewportPoint([Float(p.x), Float(1 - p.y)], quarterTurns: turns, displayTransform: display)
            try expect(abs(mapped.x - Float(expected.x)) < 0.00001 && abs(mapped.y - Float(expected.y)) < 0.00001,
                       "Vision orientation and ARKit viewport must agree in all four orientations")
        }
        let center = ARPalmGeometry.center(wrist: [0.5, 0.8], knuckles: [[0.3, 0.4], [0.4, 0.4], [0.6, 0.4], [0.7, 0.4]])
        try expect(abs(center.y - 0.5333333) < 0.00001, "Match Unity's wrist/MCP palm center")
        let points: [SIMD2<Float>] = [[0.5,0.8],[0.3,0.4],[0.4,0.4],[0.6,0.4],[0.7,0.4]]
        try expect(ARPalmGeometry.sample(points: points, confidence: [1,1,1,0,0]) != nil, "One occluded finger must not lose a reliable palm")
        try expect(ARPalmGeometry.sample(points: points, confidence: [0,1,1,1,1]) == nil, "A wrist is required")
        let sample = ARPalmSample(center: [0.5,0.5], index: [0.4,0.5], little: [0.6,0.5], wrist: [0.5,0.65], knuckles: [0.5,0.45])
        func observation(_ timestamp: Double, x: Float = 0) -> ARPalmObservation {
            var camera = matrix_identity_float4x4
            camera.columns.3.x = x
            return ARPalmObservation(hand: sample, cameraToWorld: camera, inverseProjection: matrix_identity_float4x4, timestamp: timestamp)
        }
        var state = ARPalmPlacementState()
        try expect(state.observe(observation(10)), "Resolve an image-time hand position")
        let initial = state.update(at: 10.1, deltaTime: 1.0 / 30)!
        try expect(state.isFresh(at: 10.1), "Fresh hand permits capture")
        try expect(!state.observe(observation(9, x: 5)), "Older observations cannot move the hand")
        let held = state.update(at: 10.5, deltaTime: 1.0 / 30)!
        try expect(!state.isFresh(at: 10.5) && held == initial, "Brief loss holds the world point and blocks capture")
        try expect(state.update(at: 10.91, deltaTime: 1.0 / 30) == nil, "Hide after the recovery interval")
        try expect(state.observe(observation(12, x: 1)), "Reacquire after camera movement")
        let reacquired = state.update(at: 12.01, deltaTime: 1.0 / 30)!
        try expect(abs(reacquired.x - 1) < 0.00001, "Reacquisition does not interpolate from an expired world position")

        let original = ARCaptureSettings()
        try expect(original.character == .ponix, "New cameras default to Ponix")
        try expect(ARCharacter.selectableCases == [.ponix, .neopjuk, .ponixVsNeopjuk,
            .oiDinosaur, .oiCat, .oiBaseball, .oiFarmer, .oiSportswear], "Offer the requested mascot catalog")
        for character in [ARCharacter.doni, .neopjukAnimated, .neopjuk] {
            var saved = original
            saved.character = character
            try expect(try JSONDecoder().decode(ARCaptureSettings.self, from: JSONEncoder().encode(saved)) == saved,
                       "Previously saved mascot records remain readable")
        }
        let bytes = try JSONEncoder().encode(original)
        let legacy = try JSONDecoder().decode(ARCaptureSettings.self, from: bytes)
        try expect(legacy.placementMode == nil && legacy.palmHeight == nil, "Legacy records retain floor defaults")
        var palm = legacy
        palm.placementMode = .palm; palm.palmHeight = 0.065; palm.palmRotation = 20
        try expect(try JSONDecoder().decode(ARCaptureSettings.self, from: JSONEncoder().encode(palm)) == palm,
                   "Palm settings round-trip without changing floor height")
        print("PASS: single-flight palm inference, stale callback rejection, orientation/aspect-fill, partial joints, depth expiry/reacquisition, legacy settings")
    }
}
