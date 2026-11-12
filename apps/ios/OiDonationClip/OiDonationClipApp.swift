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
#if DEBUG
    /// A new session per presentation so reopening always starts a fresh puzzle.
    @State private var postcardPrototypeSession: PostcardPrototypeSession?
#endif

    private var postcardPrototypeAction: (() -> Void)? {
#if DEBUG
        { postcardPrototypeSession = PostcardPrototypeSession() }
#else
        nil
#endif
    }

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
            AppClipExperienceView(
                storyRepository: RealStoryRepository(),
                invocation: invocation,
                onRequestFullApp: { isOverlayPresented = true },
                onOpenPostcardPrototype: postcardPrototypeAction
            ) { story, id in
                AppClipStorySafetyButton(story: story, id: id)
            }
#if DEBUG
            .fullScreenCover(item: $postcardPrototypeSession) { session in
                ARPostcardPrototypeFlowView().id(session.id)
            }
#endif
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                invocation = AppClipInvocation(url: activity.webpageURL)
            }
            .onOpenURL { url in invocation = AppClipInvocation(url: url) }
            .appStoreOverlay(isPresented: $isOverlayPresented) {
                SKOverlay.AppClipConfiguration(position: .bottom)
            }
        }
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

#if DEBUG
private struct PostcardPrototypeSession: Identifiable {
    let id = UUID()
}
#endif
