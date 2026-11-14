//
//  CampusNFCPostcardRoute.swift
//  OiDonation
//
//  Created by jiwon hong on 11/14/26.
//

import SwiftUI

/// An NFC postcard tag opened in the installed full app (#324).
struct CampusNFCPostcardRoute: Hashable {
    let tagID: String
}

/// Resolves a tag to its linked public story, then shows the same cucumber summary the map opens.
///
/// The App Clip shows a scratch postcard instead; the full app reuses its existing summary view.
struct CampusNFCPostcardView<Summary: View>: View {
    let route: CampusNFCPostcardRoute
    let repository: any StoryRepository
    let store: CampusStoryStore
    let remote: OiRemoteStore
    @ViewBuilder var summary: (CampusStory) -> Summary

    private enum Phase: Equatable { case resolving, waitingForStory(UUID), unavailable, failed }
    @State private var phase: Phase = .resolving
    @State private var attempt = 0
    @State private var refreshedForMissingStory = false

    private var story: CampusStory? {
        guard case .waitingForStory(let id) = phase else { return nil }
        return store.stories.first { UUID(uuidString: $0.id) == id }
    }

    var body: some View {
        Group {
            if let story {
                summary(story)
            } else {
                switch phase {
                case .resolving, .waitingForStory:
                    ProgressView("엽서를 불러오는 중")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable:
                    ContentUnavailableView("이 엽서는 지금 볼 수 없어요", systemImage: "wave.3.right",
                                           description: Text("공개가 끝났거나 연결이 바뀐 엽서예요."))
                case .failed:
                    ContentUnavailableView {
                        Label("엽서를 불러오지 못했어요", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("인터넷 연결을 확인하고 다시 시도해 주세요.")
                    } actions: {
                        Button("다시 시도") {
                            Task { if !remote.hasLoadedRemote { await remote.refresh() } }
                            attempt += 1
                        }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .task(id: attempt) { await resolve() }
        .task(id: waitKey) { await waitForStory() }
    }

    /// Re-evaluated whenever the shared story list or the remote loading state changes.
    private var waitKey: String {
        "\(phase)/\(store.stories.count)/\(remote.hasLoadedRemote)/\(remote.isRefreshing)/\(remote.loadError ?? "")"
    }

    private func resolve() async {
        phase = .resolving
        refreshedForMissingStory = false
        do {
            guard let value = try await repository.fetchNFCPostcardStoryID(tag: route.tagID),
                  let id = UUID(uuidString: value) else {
                if !Task.isCancelled { phase = .unavailable }
                return
            }
            guard !Task.isCancelled else { return }
            phase = .waitingForStory(id)
        } catch {
            if !Task.isCancelled { phase = .failed }
        }
    }

    /// The map's story list may still be loading on a cold launch, or may predate a just-approved story.
    private func waitForStory() async {
        guard case .waitingForStory(let id) = phase, story == nil, !remote.isRefreshing else { return }
        guard remote.hasLoadedRemote else {
            // The map list failed to load; offer a retry instead of an endless spinner.
            if remote.loadError != nil { phase = .failed }
            return
        }
        // Already in the loaded public list: the map store picks it up on its next synchronization.
        if remote.stories.contains(where: { $0.id == id }) { return }
        if !refreshedForMissingStory {
            refreshedForMissingStory = true
            await remote.refresh()
            guard !Task.isCancelled, phase == .waitingForStory(id) else { return }
            if remote.stories.contains(where: { $0.id == id }) { return }
        }
        // Loaded and refreshed, yet not in the public list (hidden, blocked author or removed).
        if story == nil { phase = .unavailable }
    }
}
