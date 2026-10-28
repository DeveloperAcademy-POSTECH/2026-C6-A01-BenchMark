//
//  OiDonationClipApp.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import SwiftUI
import CoreText

@main
struct OiDonationClipApp: App {
    init() {
        if let url = Bundle.main.url(forResource: "PearToucan-Regular", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "PearToucan-Regular", withExtension: "ttf", subdirectory: "Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ar-flow-preview") {
            ARGameFlowView(
                story: Story(
                    storyID: "preview-story",
                    donorID: UUID(),
                    title: "화성갈끄니까오이",
                    content: "AR 게임 실기기 확인용 이야기"
                ),
                onBack: {}
            )
        } else if ProcessInfo.processInfo.arguments.contains("-ar-intro-preview") {
            ARGameIntroView(
                cucumberName: "화성갈끄니까오이",
                targetCount: 3,
                timeLimitSeconds: 30,
                onBack: {},
                onStart: {}
            )
        } else {
            ContentView(storyRepository: RealStoryRepository())
        }
        #else
        ContentView(storyRepository: RealStoryRepository())
        #endif
    }
}
