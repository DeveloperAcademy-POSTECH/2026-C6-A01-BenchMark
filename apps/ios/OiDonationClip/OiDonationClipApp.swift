//
//  OiDonationClipApp.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import SwiftUI
import CoreText
import StoreKit

@main
struct OiDonationClipApp: App {
    @State private var isOverlayPresented = false
    @State private var invocation: AppClipInvocation?
    /// A new session per presentation so reopening always starts with a fresh card.
    @State private var scratchPostcardSession: ScratchPostcardSession?
    private let storyRepository = RealStoryRepository()

    init() {
        for name in [
            "Paperlogy-2ExtraLight",
            "Paperlogy-3Light",
            "Paperlogy-4Regular",
            "Paperlogy-5Medium",
            "Paperlogy-6SemiBold",
            "Paperlogy-7Bold",
            "Yangjin-v0.9"
        ] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppClipExperienceView(
                storyRepository: storyRepository,
                invocation: invocation,
                onRequestFullApp: { isOverlayPresented = true }
            ) { story, id in
                AppClipStorySafetyButton(story: story, id: id)
            }
            .fullScreenCover(item: $scratchPostcardSession) { session in
                ScratchPostcardScreen(tagID: session.tagID, repository: storyRepository,
                                      onClose: { scratchPostcardSession = nil })
                    .id(session.id)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                handleInvocation(activity.webpageURL)
            }
            .onOpenURL { url in handleInvocation(url) }
            .appStoreOverlay(isPresented: $isOverlayPresented) {
                SKOverlay.AppClipConfiguration(position: .bottom)
            }
        }
    }
}

extension OiDonationClipApp {
    /// NFC postcard links open the scratch postcard for the tag; every other link keeps the existing story flow.
    private func handleInvocation(_ url: URL?) {
        if let url, let tag = AppClipLink.postcardID(in: url) {
            scratchPostcardSession = ScratchPostcardSession(tagID: tag)
        }
        invocation = AppClipInvocation(url: url)
    }
}

private struct AppClipStorySafetyButton: View {
    let story: Story
    let id: UUID
    @State private var showingSafety = false

    var body: some View {
        Button("신고 및 차단") { showingSafety = true }
            .frame(minHeight: 44)
            .sheet(isPresented: $showingSafety) {
                OiContentSafetyView(storyID: id, authorID: story.donorID, authorName: story.donorDisplayName)
            }
    }
}

private struct ScratchPostcardSession: Identifiable {
    let id = UUID()
    let tagID: String
}
