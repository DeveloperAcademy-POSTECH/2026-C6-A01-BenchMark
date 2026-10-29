// Created by 이돈혁

import Foundation

enum ARRecoveryIssue: Equatable, Identifiable {
    case unsupported
    case cameraDenied
    case cameraRestricted
    case interrupted
    case sessionFailure(String)
    case characterLoadFailure(String)

    var id: String {
        switch self {
        case .unsupported: return "unsupported"
        case .cameraDenied: return "cameraDenied"
        case .cameraRestricted: return "cameraRestricted"
        case .interrupted: return "interrupted"
        case .sessionFailure: return "sessionFailure"
        case .characterLoadFailure: return "characterLoadFailure"
        }
    }

    var title: String {
        switch self {
        case .unsupported: return "AR을 사용할 수 없어요"
        case .cameraDenied: return "카메라 접근을 허용해 주세요"
        case .cameraRestricted: return "카메라 사용이 제한되어 있어요"
        case .interrupted: return "카메라가 잠시 중단됐어요"
        case .sessionFailure: return "AR 카메라를 다시 시작해 주세요"
        case .characterLoadFailure: return "캐릭터를 불러오지 못했어요"
        }
    }

    var message: String {
        switch self {
        case .unsupported:
            return "이 기기에서는 AR 촬영을 지원하지 않아요. 지원되는 실제 iPhone에서 사용해 주세요."
        case .cameraDenied:
            return "설정에서 오이기부의 카메라 접근을 허용한 뒤 돌아와 주세요."
        case .cameraRestricted:
            return "기기의 사용 제한으로 카메라를 사용할 수 없어요. 스크린 타임 또는 기기 관리 설정을 확인해 주세요."
        case .interrupted:
            return "다른 작업이 끝나면 카메라가 다시 연결돼요. 돌아오지 않으면 재시도하거나 카메라를 닫아 주세요."
        case .sessionFailure(let detail):
            return "다시 시작하면 캐릭터 위치를 다시 지정해야 해요. 촬영 결과와 설정은 유지됩니다.\n\(detail)"
        case .characterLoadFailure(let detail):
            return "선택한 캐릭터와 촬영 결과는 유지됩니다. 다시 불러오거나 다른 캐릭터를 선택해 주세요.\n\(detail)"
        }
    }

    var canOpenSettings: Bool { self == .cameraDenied }

    var canRetry: Bool {
        switch self {
        case .interrupted, .sessionFailure, .characterLoadFailure: return true
        case .unsupported, .cameraDenied, .cameraRestricted: return false
        }
    }
}

/// Owns start attempts across permission suspension, interruption, and explicit recovery.
struct ARSessionLifecycle {
    struct StartAttempt: Equatable {
        fileprivate let generation: UInt64
        let requiresTrackingReset: Bool
    }

    private enum Phase: Equatable {
        case inactive
        case awaitingStart
        case starting(UInt64)
        case running
        case interrupted
        case failed
    }

    private var phase: Phase = .inactive
    private var generation: UInt64 = 0
    private var wantsRunning = false
    private var requiresTrackingReset = false

    var starting: Bool {
        if case .starting = phase { return true }
        return false
    }
    var running: Bool { wantsRunning && phase == .running }
    var acceptsSessionCallbacks: Bool {
        wantsRunning && (phase == .running || phase == .interrupted)
    }

    mutating func beginStart(recovering: Bool = false) -> StartAttempt? {
        guard !starting, !running else { return nil }
        guard recovering || (phase != .failed && phase != .interrupted) else { return nil }
        generation &+= 1
        wantsRunning = true
        phase = .starting(generation)
        return StartAttempt(generation: generation, requiresTrackingReset: requiresTrackingReset)
    }

    func isCurrent(_ attempt: StartAttempt) -> Bool {
        wantsRunning && phase == .starting(attempt.generation)
    }

    @discardableResult
    mutating func completeStart(_ attempt: StartAttempt) -> Bool {
        guard isCurrent(attempt) else { return false }
        phase = .running
        requiresTrackingReset = false
        return true
    }

    @discardableResult
    mutating func rejectStart(_ attempt: StartAttempt) -> Bool {
        guard isCurrent(attempt) else { return false }
        phase = .awaitingStart
        return true
    }

    mutating func pause() {
        generation &+= 1
        wantsRunning = false
        phase = .inactive
    }

    @discardableResult
    mutating func interrupt() -> Bool {
        guard running else { return false }
        phase = .interrupted
        return true
    }

    @discardableResult
    mutating func endInterruption() -> Bool {
        guard wantsRunning, phase == .interrupted else { return false }
        phase = .running
        return true
    }

    @discardableResult
    mutating func fail() -> Bool {
        guard acceptsSessionCallbacks else { return false }
        phase = .failed
        requiresTrackingReset = true
        return true
    }
}
