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
    /// A new session per presentation so reopening always starts with a fresh card.
    @State private var scratchPostcardSession: ScratchPostcardSession?
    /// False until the system hands over the invocation URL, so the start view never shows before a postcard (#347).
    @State private var hasRoute = false
    private let storyRepository = RealStoryRepository()

    init() {
        for name in [
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
        // Connect while the system is still handing over the invocation URL (#348).
        Task { [storyRepository] in await storyRepository.warmUpConnection() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // An NFC postcard is the root screen, not a cover over the story list (#347).
                if let scratchPostcardSession {
                    ScratchPostcardScreen(tagID: scratchPostcardSession.tagID, repository: storyRepository)
                        .id(scratchPostcardSession.id)
                } else if hasRoute {
                    // Opened without an NFC tag (App Library, shared default link, review): Figma `6005:5306` (#351).
                    AppClipStartView(onDownload: { isOverlayPresented = true })
                } else {
                    Color.white
                        .ignoresSafeArea()
                        .task {
                            // A launch without a URL (e.g. reopened from the App Library) shows the start view.
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
    /// NFC postcard links open the scratch postcard for the tag; every other link shows the start view (#351).
    private func handleInvocation(_ url: URL?) {
        hasRoute = true
        if let url, let tag = AppClipLink.postcardID(in: url) {
            // The story list is not built for a postcard, so it does not load stories in the background.
            scratchPostcardSession = ScratchPostcardSession(tagID: tag)
            return
        }
        scratchPostcardSession = nil
    }
}

private struct ScratchPostcardSession: Identifiable {
    let id = UUID()
    let tagID: String
}
