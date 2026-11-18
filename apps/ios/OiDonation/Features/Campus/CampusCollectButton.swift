//
//  CampusCollectButton.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

/// `수집하기` (#399): anyone can scratch the postcard, wherever they are. Signing in is asked here, when the
/// button is tapped, because the postcard is saved to the account. Example cucumbers are never collected.
struct CampusCollectButton: View {
    let story: CampusStory
    let store: CampusStoryStore
    var fontSize: CGFloat = 16

    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var showingSignIn = false

    private var isExample: Bool { story.isExample || store.isExample }
    private var needsSignIn: Bool { Self.needsSignIn(remote) }

    static func needsSignIn(_ remote: OiRemoteStore?) -> Bool {
        guard let remote else { return true }
        return remote.account == nil || remote.needsReauthentication
    }

    var body: some View {
        Button(action: collect) {
            Text(isExample ? "예시 카드" : "수집하기").font(CampusStyle.semibold(fontSize))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white)
                .background(Color(oiRGB: 0x708C40), in: RoundedRectangle(cornerRadius: 20))
        }
        .disabled(isExample)
        .buttonStyle(.plain)
        .accessibilityIdentifier("campus.collect")
        .sheet(isPresented: $showingSignIn) {
            if let remote {
                NavigationStack {
                    MYSettingsView(remote: remote)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("닫기") { showingSignIn = false }
                            }
                        }
                }
            }
        }
        // Continue to the postcard as soon as the sign-in finishes.
        .onChange(of: needsSignIn) { _, needsSignIn in
            guard showingSignIn, !needsSignIn else { return }
            showingSignIn = false
            store.collect(story)
        }
    }

    private func collect() {
        if needsSignIn { showingSignIn = true } else { store.collect(story) }
    }
}
