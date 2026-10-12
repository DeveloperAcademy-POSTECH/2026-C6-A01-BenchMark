//
//  OiDonationApp.swift
//  OiDonation
//
//  Created by jiwon hong on 10/8/26.
//

import SwiftUI

@main
struct OiDonationApp: App {
    @UIApplicationDelegateAdaptor(ARRecordingOrientation.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            RootTabView(container: .pilot)
        }
    }
}
