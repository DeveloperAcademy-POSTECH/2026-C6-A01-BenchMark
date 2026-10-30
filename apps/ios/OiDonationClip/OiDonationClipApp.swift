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
    @State private var previewCollectionStore = StoryCollectionStore()
    @State private var isOverlayPresented = false

    init() {
        for name in ["PearToucan-Regular", "KIM-WILDgag-Bold", "Griun_OMIRI-Rg", "Mona12TextKR", "Paperlogy-4Regular", "Paperlogy-6SemiBold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-reset-preview-collection") {
                        previewCollectionStore.remove(storyID: "preview-story")
                    }
                    #endif
                }
                .appStoreOverlay(isPresented: $isOverlayPresented) {
                    SKOverlay.AppClipConfiguration(position: .bottom)
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ar-failure-preview") {
            ARGameFailureView(onRetry: {})
        } else if ProcessInfo.processInfo.arguments.contains("-story-card-preview") {
            AppClipStoryCardView(
                experience: previewExperience,
                isCollected: previewCollectionStore.contains(storyID: previewExperience.story.storyID),
                onCollect: {
                    previewCollectionStore.collect(previewExperience.storyCard)
                    isOverlayPresented = true
                },
                onCancel: {}
            )
        } else if ProcessInfo.processInfo.arguments.contains("-ar-flow-preview") {
            ARGameFlowView(
                experience: previewExperience,
                onBack: {},
                onRequestFullApp: { isOverlayPresented = true }
            )
        } else if ProcessInfo.processInfo.arguments.contains("-ar-intro-preview") {
            ARGameIntroView(
                cucumberName: "화성갈끄니까오이",
                cucumberImageURL: nil,
                targetCount: 3,
                timeLimitSeconds: 30,
                onBack: {},
                onStart: {}
            )
        } else {
            ContentView(
                storyRepository: RealStoryRepository(),
                onRequestFullApp: { isOverlayPresented = true }
            )
        }
        #else
        ContentView(
            storyRepository: RealStoryRepository(),
            onRequestFullApp: { isOverlayPresented = true }
        )
        #endif
    }

    private var previewExperience: AppClipExperience {
        AppClipExperience(
            story: Story(
                storyID: "preview-story",
                donorID: UUID(),
                donorDisplayName: "20학번 디벨로퍼학과 신예은",
                title: "화성갈끄니까오이",
                content: "2024년 처음 만들어진 PSI 항공우주연구회의 최종목표인 화성 도착에 성공을 기원하며...",
                publishedAt: Date(timeIntervalSince1970: 1_792_724_400),
                location: StoryLocation(locationID: "preview-location", displayName: "포항공과대학교 지곡회관 옆 연못길"),
                tags: ["기대감", "미래"],
                cucumberID: "preview-cucumber",
                cucumberName: "화성오이",
                cucumberImageURL: nil
            ),
            storyCard: StoryCard(
                cardID: "preview-card",
                storyID: "preview-story",
                imageURL: Bundle.main.url(forResource: "AppClipStoryCardPreview", withExtension: "png")
                    ?? URL(fileURLWithPath: "/AppClipStoryCardPreview.png")
            )
        )
    }
}
