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
        case success
        case failure
        case unavailable
    }

    private(set) var state: State = .intro

    func requestPermission() {
        guard state == .intro else { return }
        state = .requestingPermission
    }

    func permissionGranted() {
        guard state == .requestingPermission else { return }
        state = .playing
    }

    func permissionDenied() {
        guard state == .requestingPermission else { return }
        state = .unavailable
    }

    func finishGame(succeeded: Bool) {
        guard state == .playing else { return }
        state = succeeded ? .success : .failure
    }

    func reset() {
        state = .intro
    }
}
