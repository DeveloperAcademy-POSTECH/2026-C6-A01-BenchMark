//
//  CampusMapMotion.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/5/26.
//

import Foundation

/// Logarithmic distance gives the same resistance at either end of a pinch.
enum CampusMapMotion {
    private static let stretch: Float = 0.18
    private static let resistance: Float = 0.55

    static func resistedRadius(logRadius: Float, within limits: ClosedRange<Float>) -> Float {
        let lower = log(limits.lowerBound)
        let upper = log(limits.upperBound)
        let bound = min(upper, max(lower, logRadius))
        let distance = logRadius - bound
        let offset = stretch * resistance * distance / (stretch + resistance * abs(distance))
        return exp(bound + offset)
    }

    static func inputLogRadius(for radius: Float, within limits: ClosedRange<Float>) -> Float {
        let value = log(radius)
        let bound = min(log(limits.upperBound), max(log(limits.lowerBound), value))
        let offset = value - bound
        let distance = min(abs(offset), stretch * 0.9999)
        let unresisted = distance * stretch / (resistance * (stretch - distance))
        return bound + (offset < 0 ? -unresisted : unresisted)
    }

    static func releaseVelocity(_ velocity: Float, logRadius: Float, within limits: ClosedRange<Float>) -> Float {
        guard velocity.isFinite else { return 0 }
        let bound = min(log(limits.upperBound), max(log(limits.lowerBound), logRadius))
        let distance = abs(logRadius - bound)
        let ratio = stretch / (stretch + resistance * distance)
        let slope = distance > 0 ? resistance * ratio * ratio : 1
        return min(2.5, max(-2.5, velocity * slope))
    }

    struct Spring {
        struct Sample {
            let radius: Float
            let progress: Float
            let isComplete: Bool
        }

        let destination: Float
        private let origin: Float
        private let velocity: Float

        init(from radius: Float, to destination: Float, velocity: Float = 0) {
            self.destination = destination
            origin = log(radius)
            self.velocity = velocity
        }

        func sample(at elapsed: TimeInterval) -> Sample {
            let time = Float(max(0, elapsed))
            let frequency: Float = 18
            let decay = exp(-frequency * time)
            let destinationLog = log(destination)
            let offset = origin - destinationLog
            let coefficient = velocity + frequency * offset
            let value = destinationLog + (offset + coefficient * time) * decay
            let currentVelocity = (velocity - frequency * coefficient * time) * decay
            let progress = 1 - (1 + frequency * time) * decay
            let complete = time >= 0.9 || (
                abs(value - destinationLog) < 0.0001 && abs(currentVelocity) < 0.002 && progress > 0.999
            )
            return Sample(radius: complete ? destination : exp(value),
                          progress: complete ? 1 : progress, isComplete: complete)
        }
    }
}
