//
//  OiContinuationList.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//

import SwiftUI

/// One public-visibility contract for the parent story and the owner's incoming list.
struct OiContinuationList: View {
    var parent: UUID? = nil
    var store: CampusStoryStore? = nil
    var emptyContent: (() -> AnyView)? = nil
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @Environment(CampusStoryStore.self) private var sharedStore: CampusStoryStore?
    @State private var rows: [OiStoryContinuation] = []
    @State private var cursor: OiContinuationCursor?
    @State private var total: Int?
    @State private var isLoading = false
    @State private var failure: String?
    @State private var unsupported = false
    @State private var requestID = UUID()
    @State private var loadedContext: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if loadedContext != nil && loadedContext != requestContext {
                ProgressView("이어진 이야기 불러오는 중")
            } else if let emptyContent {
                if rows.isEmpty, !isLoading, total == 0 || failure != nil || unsupported {
                    emptyContent()
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        continuationRows
                        loadingAndPagination
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                list
            }
        }
        .task(id: requestContext) {
            await load(reset: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isLoading { Task { await load(reset: true) } }
        }
        .onChange(of: catalogIDs) { previous, current in
            guard let previous, let current else { return }
            let removed = previous.subtracting(current)
            if parent.map(removed.contains) == true {
                requestID = UUID(); rows = []; cursor = nil; total = nil; isLoading = false
            } else if rows.contains(where: { removed.contains($0.childStoryId) }) {
                rows.removeAll { removed.contains($0.childStoryId) }
                Task { await load(reset: true) }
            }
        }
        .accessibilityIdentifier("oi.continuations.list")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(parent == nil ? "내 이야기에 이어진 이야기" : "이 이야기에서 이어진 이야기")
                    .font(CampusStyle.semibold(16))
                Text("공개된 이야기 연결이며 실제 기부·납입이나 학교 확인 내역이 아니에요.")
                    .font(.caption).foregroundStyle(.secondary)
                if let total, total > 0, failure == nil, !unsupported {
                    Text("공개된 이어진 이야기 \(total)개").font(.subheadline)
                }
                if rows.isEmpty && !isLoading && (total != nil || failure != nil || unsupported) {
                    ContentUnavailableView("아직 이어진 이야기가 없어요", systemImage: "link")
                }
                continuationRows
                loadingAndPagination
            }.padding(20)
        }
        .refreshable { await load(reset: true) }
    }

    private var continuationRows: some View {
        ForEach(rows) { row in
            if let remote {
                let story = remote.campusStory(row.story)
                NavigationLink(value: CampusDestination.summary(story.id)) {
                    OiCucumberCard(name: story.title, tags: story.tags, donor: story.donor,
                        title: story.storyTitle) { CampusCucumberPortrait(story: story) }
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("oi.continuation.\(row.id.uuidString)")
            }
        }
    }

    @ViewBuilder private var loadingAndPagination: some View {
        if isLoading { ProgressView("이어진 이야기 불러오는 중") }
        if cursor != nil && !isLoading {
            Button("더 보기") { Task { await load(reset: false) } }
        }
    }

    private var catalogIDs: Set<UUID>? {
        guard let remote, remote.hasLoadedRemote else { return nil }
        return Set(remote.stories.map(\.id))
    }

    private var requestContext: String {
        "\(parent?.uuidString ?? "mine")/\(remote?.continuationPrivacyKey ?? "public")"
    }

    private func load(reset: Bool) async {
        let context = requestContext
        if loadedContext != context {
            requestID = UUID(); rows = []; cursor = nil; total = nil
            loadedContext = context
        }
        guard let remote else {
            unsupported = true
            return
        }
        guard reset || !isLoading else { return }
        if reset { requestID = UUID() }
        let started = requestID
        failure = nil; unsupported = false; isLoading = true
        defer { if requestID == started { isLoading = false } }
        do {
            let result = try await remote.storyContinuations(parent: parent, mine: parent == nil,
                cursor: reset ? nil : cursor)
            try Task.checkCancellation()
            guard requestID == started, requestContext == context else { return }
            var known = reset ? Set<UUID>() : Set(rows.map(\.id))
            let incoming = result.items.filter { known.insert($0.id).inserted }
            rows = reset ? incoming : rows + incoming
            cursor = result.nextCursor; total = result.total
            if let store = store ?? sharedStore {
                let incoming = result.items.map { remote.campusStory($0.story) }
                let ids = Set(incoming.map(\.id))
                store.synchronize(stories: store.stories.filter { !ids.contains($0.id) } + incoming, collected: store.collected)
            }
        } catch is CancellationError { }
        catch is OiContinuationError {
            if !Task.isCancelled && requestID == started && requestContext == context {
                unsupported = true
            }
        }
        catch {
            if !Task.isCancelled && requestID == started && requestContext == context {
                failure = "이어진 이야기를 불러오지 못했어요. 다시 시도해 주세요."
            }
        }
    }
}
