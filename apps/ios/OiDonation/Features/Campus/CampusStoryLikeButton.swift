//
//  CampusStoryLikeButton.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import SwiftUI
import Observation

/// Cached state belongs to one story/account; old reads cannot overwrite a newer toggle.
@MainActor @Observable
final class CampusStoryLikeState {
    struct Context: Equatable {
        let storyID: UUID
        let accountID: UUID?
    }

    private(set) var context: Context?
    private(set) var like: OiStoryLike?
    private(set) var unsupported = false
    private(set) var isUpdating = false
    var message: String?
    private var request = UUID()

    private func select(_ next: Context) {
        guard context != next else { return }
        context = next; like = nil; unsupported = false; isUpdating = false; message = nil
        request = UUID()
    }

    func load(_ context: Context, fetch: () async throws -> OiStoryLike?) async {
        guard !Task.isCancelled else { return }
        select(context)
        guard !isUpdating else { return }
        let started = UUID(); request = started
        do {
            let value = try await fetch()
            guard !Task.isCancelled, self.context == context, request == started else { return }
            like = value; unsupported = false
        } catch {
            guard !Task.isCancelled, self.context == context, request == started else { return }
            if error is OiStoryLikeError { unsupported = true }
            // A refresh failure retains a value only within the same story/account.
        }
    }

    func set(_ context: Context, save: () async throws -> OiStoryLike) async {
        guard !Task.isCancelled else { return }
        select(context)
        guard !isUpdating else { return }
        let started = UUID(); request = started
        isUpdating = true; message = nil
        defer { if self.context == context, request == started { isUpdating = false } }
        do {
            let value = try await save()
            guard !Task.isCancelled, self.context == context, request == started else { return }
            withAnimation(.snappy(duration: 0.2)) { like = value; unsupported = false }
        } catch {
            guard !Task.isCancelled, self.context == context, request == started else { return }
            if error is OiStoryLikeError { unsupported = true }
            else if !(error is CancellationError) {
                message = "좋아요를 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }
}

/// Heart + count shown beside 수집하기 on the cucumber summary (#504).
/// One like per account: the server keeps a unique row and the toggle is idempotent.
struct CampusStoryLikeButton: View {
    let story: CampusStory
    let store: CampusStoryStore

    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var state = CampusStoryLikeState()
    @State private var showingSignIn = false

    private var storyID: UUID? { UUID(uuidString: story.id) }
    private var context: CampusStoryLikeState.Context? {
        storyID.map { .init(storyID: $0, accountID: remote?.account?.id) }
    }
    private var like: OiStoryLike? { state.context == context ? state.like : nil }
    private var isUpdating: Bool { state.context == context && state.isUpdating }
    private var unsupported: Bool { state.context == context && state.unsupported }
    private var message: String? { state.context == context ? state.message : nil }
    private var isExample: Bool { story.isExample || store.isExample }
    private var liked: Bool { like?.liked ?? false }
    /// Figma `Like` (6862:16197): 68×46 capsule, heart and count side by side.
    private let likedColor = Color(oiRGB: 0xB0C85B)
    private let idleBorder = Color(oiRGB: 0xC2C2C2)
    private let idleText = Color(oiRGB: 0x535353)

    var body: some View {
        Group {
            if !unsupported && !isExample {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                        Text(like.map { String($0.count) } ?? "–")
                            .font(CampusStyle.medium(16)).tracking(0.32).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(liked ? likedColor : idleText)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .frame(width: 68, height: 46)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(liked ? likedColor : idleBorder, lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(isUpdating)
                .accessibilityLabel(liked ? "좋아요 취소" : "좋아요")
                .accessibilityValue(like.map { "좋아요 \($0.count)개" } ?? "불러오는 중")
                .accessibilityIdentifier("campus.summary.like")
            }
        }
        .task(id: "\(story.id)/\(remote?.account?.id.uuidString ?? "public")/\(remote?.revision ?? 0)") { await load() }
        .sheet(isPresented: $showingSignIn) {
            if let remote {
                NavigationStack {
                    MYSettingsView(remote: remote)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showingSignIn = false } } }
                }
            }
        }
        .onChange(of: CampusCollectButton.needsSignIn(remote)) { _, needsSignIn in
            guard showingSignIn, !needsSignIn else { return }
            showingSignIn = false
            Task { await set(liked: true) }
        }
        .alert("좋아요", isPresented: Binding(get: { message != nil }, set: { if !$0 { state.message = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func toggle() {
        if CampusCollectButton.needsSignIn(remote) { showingSignIn = true; return }
        Task { await set(liked: !liked) }
    }

    private func load() async {
        guard let remote, !isExample, let context else { return }
        await state.load(context) { try await remote.storyLike(context.storyID) }
    }

    private func set(liked wanted: Bool) async {
        guard let remote, !isUpdating, let context else { return }
        await state.set(context) { try await remote.setStoryLike(context.storyID, liked: wanted) }
    }
}
