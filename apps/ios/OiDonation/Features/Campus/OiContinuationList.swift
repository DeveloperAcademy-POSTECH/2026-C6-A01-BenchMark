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
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @Environment(CampusStoryStore.self) private var sharedStore: CampusStoryStore?
    @State private var rows: [OiStoryContinuation] = []
    @State private var cursor: OiContinuationCursor?
    @State private var total: Int?
    @State private var isLoading = false
    @State private var failure: String?
    @State private var unsupported = false
    @State private var requestID = UUID()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(parent == nil ? "내 이야기에 이어진 이야기" : "이 이야기에서 이어진 이야기")
                    .font(CampusStyle.semibold(16))
                Text("공개된 이야기 연결이며 실제 기부·납입이나 학교 확인 내역이 아니에요.")
                    .font(.caption).foregroundStyle(.secondary)
                if let total { Text("공개된 이어진 이야기 \(total)개").font(.subheadline) }
                if unsupported {
                    ContentUnavailableView("이어진 이야기 준비 중", systemImage: "link")
                } else if let failure {
                    Text(failure).font(.footnote)
                    Button("다시 시도") { Task { await load(reset: true) } }
                } else if rows.isEmpty && !isLoading && total != nil {
                    ContentUnavailableView("아직 이어진 이야기가 없어요", systemImage: "link")
                }
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
                if isLoading { ProgressView("이어진 이야기 불러오는 중") }
                if cursor != nil && !isLoading {
                    Button("더 보기") { Task { await load(reset: false) } }
                }
            }.padding(20)
        }
        .refreshable { await load(reset: true) }
        .task(id: "\(parent?.uuidString ?? "mine")/\(remote?.continuationPrivacyKey ?? "public")/\(remote?.revision ?? 0)") {
            await load(reset: true)
        }
        .accessibilityIdentifier("oi.continuations.list")
    }

    private func load(reset: Bool) async {
        guard let remote else { unsupported = true; return }
        guard reset || !isLoading else { return }
        if reset { requestID = UUID(); rows = []; cursor = nil; total = nil }
        let started = requestID
        failure = nil; unsupported = false; isLoading = true
        defer { if !Task.isCancelled && requestID == started { isLoading = false } }
        do {
            let result = try await remote.storyContinuations(parent: parent, mine: parent == nil,
                cursor: reset ? nil : cursor)
            try Task.checkCancellation()
            guard requestID == started else { return }
            let known = Set(rows.map(\.id))
            rows += result.items.filter { !known.contains($0.id) }
            cursor = result.nextCursor; total = result.total
            if let store = store ?? sharedStore {
                let incoming = result.items.map { remote.campusStory($0.story) }
                let ids = Set(incoming.map(\.id))
                store.synchronize(stories: store.stories.filter { !ids.contains($0.id) } + incoming, collected: store.collected)
            }
        } catch is CancellationError { }
        catch is OiContinuationError { if !Task.isCancelled && requestID == started { unsupported = true } }
        catch { if !Task.isCancelled && requestID == started { failure = "이어진 이야기를 불러오지 못했어요. 다시 시도해 주세요." } }
    }
}
