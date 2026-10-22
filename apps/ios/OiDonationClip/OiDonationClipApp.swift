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
            ContentView(storyRepository: RealStoryRepository())
        }
    }
}
