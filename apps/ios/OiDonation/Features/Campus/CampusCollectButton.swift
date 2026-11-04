//
//  CampusCollectButton.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var campusCardProximity: @MainActor (Bool) async throws -> CampusCardProximity = { requestPermission in
        let locator = CampusCardLocation()
        defer { withExtendedLifetime(locator) {} }
        return try await locator.classify(requestPermission: requestPermission)
    }
}

struct CampusCollectButton: View {
    let story: CampusStory
    let store: CampusStoryStore

    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.campusCardProximity) private var classifyLocation
    @State private var proximity: CampusCardProximity?
    @State private var locationError: CampusCardLocationError?
    @State private var message: String?
    @State private var attempt = Attempt(action: .check)
    @State private var isWorking = false
    @State private var requestID = UUID()
    @State private var requestStatus: OiCardRequest.Status?
    @State private var showingSignIn = false

    private enum Action { case check, locate, collect, request }

    private struct Attempt {
        let id = UUID()
        let action: Action
        var owner: UUID? = nil
    }

    private var isExample: Bool { story.isExample || store.isExample }
    private var isCollected: Bool { store.collected.contains(story.id) }
    private var liveStory: OiLiveStory? {
        guard let id = UUID(uuidString: story.id) else { return nil }
        return remote?.stories.first { $0.id == id }
    }
    private var supportsLocation: Bool {
        guard !isExample, let liveStory else { return false }
        return remote?.regions.first { $0.id == liveStory.regionId }?.schoolId == "postech"
    }
    private var isOwnStory: Bool {
        guard let owner = remote?.account?.id else { return false }
        return liveStory?.userId == owner
    }
    private var action: Action {
        proximity == .near ? .collect : .request
    }
    private var title: String {
        if isExample { return "예시 카드" }
        if isCollected { return "수집 완료" }
        if !supportsLocation { return "위치 확인 불가" }
        if action == .collect { return "수집하기" }
        if isOwnStory { return "내 오이" }
        switch requestStatus {
        case .pending: return "요청 보냄"
        case .accepted: return "요청 수락됨"
        case .rejected: return "요청 거절됨"
        case nil: return "요청하기"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Button(action: startAction) {
                Group {
                    if isWorking { ProgressView().tint(.white).accessibilityHidden(true) }
                    else { Text(title).font(CampusStyle.semibold(16)).multilineTextAlignment(.center) }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white)
                .background(CampusStyle.summaryAction, in: RoundedRectangle(cornerRadius: 20))
            }
            .disabled(isExample || isCollected || !supportsLocation || isWorking ||
                      (action == .request && (isOwnStory || requestStatus != nil)))
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: isCollected)
            .accessibilityLabel(title)
            .accessibilityValue(isWorking ? "확인 중" : "")
            .accessibilityIdentifier(action == .request ? "campus.cardRequest" : "campus.collect")

            if let text = message ?? locationError?.errorDescription {
                Text(text).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let locationError, !isWorking {
                Button(locationError.offersSettings ? "위치 설정 열기" : "위치 확인", action: retryLocation)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("campus.cardLocation.retry")
            }
        }
        .task(id: attempt.id) { [current = attempt] in await run(current) }
        .onChange(of: scenePhase) { _, phase in
            let isUserAction = attempt.action == .collect || attempt.action == .request
            if phase == .background || (phase == .inactive && isUserAction) {
                proximity = nil
                locationError = nil
                isWorking = false
                attempt = Attempt(action: .check)
            } else if phase == .active, !isWorking {
                attempt = Attempt(action: .check)
            }
        }
        .onChange(of: remote?.account?.id) { _, _ in reset() }
        .onChange(of: story.id) { _, _ in reset() }
        .sheet(isPresented: $showingSignIn) {
            if let remote {
                NavigationStack {
                    MYSettingsView(remote: remote)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("닫기") { showingSignIn = false }
                            }
                        }
                }
            }
        }
    }

    private func reset() {
        requestID = UUID()
        requestStatus = nil
        message = nil
        proximity = nil
        locationError = nil
        isWorking = false
        attempt = Attempt(action: .check)
    }

    private func startAction() {
        attempt = Attempt(action: action, owner: remote?.account?.id)
    }

    private func retryLocation() {
        if locationError?.offersSettings == true, let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url) { accepted in
                if !accepted { message = "설정 앱에서 오이기부의 위치 접근을 확인해 주세요." }
            }
            return
        }
        attempt = Attempt(action: .locate)
    }

    private func run(_ current: Attempt) async {
        guard !Task.isCancelled, scenePhase == .active, supportsLocation, !isCollected,
              let remote, let storyID = liveStory?.id else { return }
        isWorking = true
        if current.action != .check { message = nil }
        defer { if current.id == attempt.id { isWorking = false } }
        do {
            if current.action != .request || locationError == nil {
                locationError = nil
                do {
                    let result = try await classifyLocation(current.action == .locate)
                    try Task.checkCancellation()
                    guard current.id == attempt.id else { return }
                    proximity = result
                } catch let error as CampusCardLocationError {
                    guard !Task.isCancelled, current.id == attempt.id else { return }
                    proximity = nil
                    locationError = error
                }
            }
            guard current.action == .collect || current.action == .request else { return }
            guard !Task.isCancelled, current.id == attempt.id, scenePhase == .active else { return }
            guard action == current.action else {
                if locationError == nil { message = "현재 지역이 바뀌었어요. 표시된 버튼을 다시 눌러 주세요." }
                return
            }
            guard remote.account?.id == current.owner, supportsLocation, !isCollected else { return }
            if current.action == .collect {
                store.collect(story)
            } else if remote.account == nil || remote.needsReauthentication {
                showingSignIn = true
            } else if !isOwnStory {
                let status = try await remote.sendCardRequest(storyID: storyID, requestID: requestID)
                guard !Task.isCancelled, current.id == attempt.id, remote.account?.id == current.owner else { return }
                requestStatus = status
            }
        } catch {
            guard !Task.isCancelled, current.id == attempt.id else { return }
            if remote.needsReauthentication { showingSignIn = true }
            else { message = error.localizedDescription }
        }
    }
}
