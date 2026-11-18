//
//  CampusStoryLikeButton.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import SwiftUI

/// Heart + count shown beside 수집하기 on the cucumber summary (#504).
/// One like per account: the server keeps a unique row and the toggle is idempotent.
struct CampusStoryLikeButton: View {
    let story: CampusStory
    let store: CampusStoryStore

    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var like: OiStoryLike?
    @State private var isUpdating = false
    @State private var unsupported = false
    @State private var showingSignIn = false
    @State private var message: String?

    private var storyID: UUID? { UUID(uuidString: story.id) }
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
        .alert("좋아요", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func toggle() {
        if CampusCollectButton.needsSignIn(remote) { showingSignIn = true; return }
        Task { await set(liked: !liked) }
    }

    private func load() async {
        guard let remote, !isExample, let id = storyID else { return }
        do { like = try await remote.storyLike(id) }
        catch is OiStoryLikeError { unsupported = true }
        catch { }   // Keep the previous value; the next appearance retries.
    }

    private func set(liked wanted: Bool) async {
        guard let remote, !isUpdating, let id = storyID else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            let row = try await remote.setStoryLike(id, liked: wanted)
            withAnimation(.snappy(duration: 0.2)) { like = row }
        } catch is OiStoryLikeError {
            unsupported = true
        } catch is CancellationError {
        } catch {
            message = "좋아요를 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}
