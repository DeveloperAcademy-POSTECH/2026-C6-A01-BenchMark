//
//  ARGameViewModel.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import Observation

@Observable
@MainActor
final class ARGameViewModel {
    enum State: Equatable {
        case intro
        case requestingPermission
        case playing
        case permissionDenied
        case success
        case failure
        case unavailable
    }

    private(set) var state: State = .intro
    private let isARSupported: () -> Bool
    private let requestCameraAccess: () async -> Bool

    init(
        isARSupported: @escaping () -> Bool,
        requestCameraAccess: @escaping () async -> Bool
    ) {
        self.isARSupported = isARSupported
        self.requestCameraAccess = requestCameraAccess
    }

    func requestPermission() {
        guard state == .intro else { return }
        state = .requestingPermission
    }

    func resolvePermission() async {
        guard state == .requestingPermission else { return }
        guard isARSupported() else {
            state = .unavailable
            return
        }

        let isGranted = await requestCameraAccess()
        guard state == .requestingPermission, !Task.isCancelled else { return }
        state = isGranted ? .playing : .permissionDenied
    }

    func finishGame(succeeded: Bool) {
        guard state == .playing else { return }
        state = succeeded ? .success : .failure
    }

    func reset() {
        state = .intro
    }
}
