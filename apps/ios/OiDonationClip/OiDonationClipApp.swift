//
//  OiDonationClipApp.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import SwiftUI

@main
struct OiDonationClipApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            /// 3-3. 실행 환경에 맞는 StoryRepository를 ContentView에 전달
            ContentView(linkParser: PublicLinkParser(allowedHost: "example.com"), storyRepository: TestStoryRepository())
#else
            ContentView(linkParser: PublicLinkParser(allowedHost: "example.com"), storyRepository: RealStoryRepository())
#endif
        }
    }
}
