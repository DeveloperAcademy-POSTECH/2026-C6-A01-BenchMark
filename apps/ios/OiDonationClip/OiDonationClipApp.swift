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
    /// False until the system hands over the invocation URL, so the story list never shows before a postcard (#347).
    @State private var hasRoute = false
    private let storyRepository = RealStoryRepository()

    init() {
        for name in [
            "Paperlogy-2ExtraLight",
            "Paperlogy-3Light",
            "Paperlogy-4Regular",
            "Paperlogy-5Medium",
            "Paperlogy-6SemiBold",
            "Paperlogy-7Bold"
        ] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // An NFC postcard is the root screen, not a cover over the story list (#347).
                if let scratchPostcardSession {
                    ScratchPostcardScreen(tagID: scratchPostcardSession.tagID, repository: storyRepository)
                        .id(scratchPostcardSession.id)
                } else if hasRoute {
                    AppClipExperienceView(
                        storyRepository: storyRepository,
                        invocation: invocation,
                        onRequestFullApp: { isOverlayPresented = true }
                    ) { story, id in
                        AppClipStorySafetyButton(story: story, id: id)
                    }
                } else {
                    Color.white
                        .ignoresSafeArea()
                        .task {
                            // A launch without a URL (e.g. reopened from the App Library) falls back to the list.
                            try? await Task.sleep(for: .seconds(1))
                            hasRoute = true
                        }
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                handleInvocation(activity.webpageURL)
            }
            .onOpenURL { url in handleInvocation(url) }
            #if DEBUG
            // Simulator hook: `simctl launch` cannot pass an App Clip invocation, so a debug build accepts one
            // from `OI_DEBUG_INVOCATION_URL` (screenshots of the postcard states, #351).
            .task {
                if let value = ProcessInfo.processInfo.environment["OI_DEBUG_INVOCATION_URL"] {
                    handleInvocation(URL(string: value))
                }
            }
            #endif
            .appStoreOverlay(isPresented: $isOverlayPresented) {
                SKOverlay.AppClipConfiguration(position: .bottom)
            }
        }
    }
}

extension OiDonationClipApp {
    /// NFC postcard links open the scratch postcard for the tag; every other link keeps the existing story flow.
    private func handleInvocation(_ url: URL?) {
        hasRoute = true
        if let url, let tag = AppClipLink.postcardID(in: url) {
            // The story list is not built for a postcard, so it does not load stories in the background.
            scratchPostcardSession = ScratchPostcardSession(tagID: tag)
            return
        }
        scratchPostcardSession = nil
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
