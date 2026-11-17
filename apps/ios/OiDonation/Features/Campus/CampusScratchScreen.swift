//
//  CampusScratchScreen.swift
//  OiDonation
//
//  Created by Jiwon Hong on 11/16/26.
//

import SwiftUI

/// The summary's `수집하기` (#399): the same scratch postcard as the App Clip, opened by story instead of NFC tag.
/// Scratching reveals the postcard; `앨범에 저장하기` saves it to the account's `수집한 기부` collection.
/// A story the account already collected opens already scratched.
struct CampusScratchScreen: View {
    let story: CampusStory
    let repository: any StoryRepository
    let remote: OiRemoteStore
    /// Opens the story list (`이어서 기부하기`).
    let onDonate: () -> Void
    /// Called once the postcard is saved, to open MY 작업실의 `수집한 기부` 탭.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var loader = ScratchPostcardLoader()
    @State private var attempt = 0
    @State private var faceAttempt = 0
    @State private var finishingSave = false
    /// Decided once when the postcard loads, so saving mid-screen never skips the scratching.
    @State private var startsRevealed: Bool?
    @State private var revealOwner: UUID?

    private struct LoadContext: Hashable {
        let attempt: Int
        let owner: UUID?
        let hydrated: Bool
    }

    private var storyUUID: UUID? { UUID(uuidString: story.id) }
    private var isSaved: Bool {
        guard let storyUUID else { return false }
        return remote.collections.contains { $0.storyId == storyUUID }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch loader.state {
            case .loaded(let postcard):
                if let startsRevealed, revealOwner == remote.account?.id {
                    ScratchPostcardView(
                        postcard: postcard,
                        validateCollection: { true },
                        // A blocked author's postcard reloads into the unavailable state.
                        onBlock: { attempt += 1 },
                        onRetryFaces: { faceAttempt += 1 },
                        fullApp: ScratchPostcardFullApp(
                            startsRevealed: startsRevealed, isSaved: isSaved,
                            onBack: { dismiss() }, onDonate: onDonate, onSave: save))
                } else {
                    loadingContent
                    backButton
                }
            case .loading:
                loadingContent
                backButton
            case .unavailable:
                ScratchPostcardStatusView(message: "이 엽서는 지금 볼 수 없어요\n비공개·차단되었거나 연결이 바뀐 엽서예요") {
                    ScratchPostcardStatusButton(title: "돌아가기") { dismiss() }
                }
                backButton
            case .failed:
                ScratchPostcardStatusView(message: "엽서를 불러오지 못했어요\n인터넷 연결을 확인하고 다시 시도해 주세요") {
                    ScratchPostcardStatusButton(title: "다시 시도") { attempt += 1 }
                }
                backButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.light)
        .task(id: faceAttempt) {
            guard faceAttempt > 0 else { return }
            await loader.retryFaces(repository: repository, usesTag: false)
        }
        .task(id: SaveConfirmation(owner: remote.account?.id, saved: isSaved)) {
            guard isSaved, let owner = remote.account?.id, let storyUUID else { return }
            await finishRecoveredSave(storyUUID, owner: owner)
        }
        .task(id: LoadContext(attempt: attempt, owner: remote.account?.id, hydrated: remote.hasLoadedRemote)) {
            guard let revealed = Self.initialRevealState(storyID: storyUUID, remote: remote) else { return }
            if startsRevealed == nil || revealOwner != remote.account?.id {
                startsRevealed = revealed
                revealOwner = remote.account?.id
            }
            await loader.load(tag: "", repository: repository, storyID: story.id)
        }
    }

    /// An empty collection is only authoritative after the account's first read completes.
    static func initialRevealState(storyID: UUID?, remote: OiRemoteStore) -> Bool? {
        guard remote.hasLoadedRemote else { return nil }
        guard let storyID else { return false }
        return remote.collections.contains { $0.storyId == storyID }
    }

    private var loadingContent: some View {
        let failedRead = !remote.hasLoadedRemote && remote.loadError != nil
        return ScratchPostcardStatusView(message: failedRead
            ? "수집한 엽서를 확인하지 못했어요\n연결을 확인하고 다시 시도해 주세요"
            : "엽서를 꺼내는 중이에요\n잠시만 기다려 주세요") {
                if failedRead {
                    ScratchPostcardStatusButton(title: "다시 시도") { Task { await remote.refresh() } }
                } else {
                    ProgressView().tint(ScratchPostcardStatusView<EmptyView>.green)
                }
            }
    }

    /// Status screens have no postcard header, so they bring their own back chevron.
    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 22))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12).padding(.top, 8)
        .accessibilityLabel("뒤로")
    }

    private struct SaveConfirmation: Equatable {
        let owner: UUID?
        let saved: Bool
    }

    private func save() async -> String? {
        guard let storyUUID, let owner = remote.account?.id else { return "로그인한 뒤 저장할 수 있어요." }
        do {
            try await remote.saveScratchCollection(id: storyUUID, owner: owner)
            await finishRecoveredSave(storyUUID, owner: owner)
            return nil
        } catch {
            return Task.isCancelled ? nil : error.localizedDescription
        }
    }

    private func finishRecoveredSave(_ id: UUID, owner: UUID) async {
        guard !finishingSave else { return }
        finishingSave = true
        defer { finishingSave = false }
        do {
            try await remote.finishScratchCollection(id: id, owner: owner, onConfirmed: onSaved)
        } catch {
            if remote.account?.id == owner, !Task.isCancelled { remote.error = error.localizedDescription }
        }
    }

}
