//
//  OiStorySafetyButton.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/6/26.
//

import SwiftUI

struct OiStorySafetyButton: View {
    let storyID: UUID
    let authorID: UUID
    let authorName: String
    var onBlock: () -> Void = {}
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var showing = false
    var body: some View {
        if remote?.account?.id != authorID {
            Button("신고 및 차단") { showing = true }.frame(minHeight: 44)
                .sheet(isPresented: $showing) {
                    OiContentSafetyView(storyID: storyID, authorID: authorID, authorName: authorName,
                        submit: reportAction, onBlock: onBlock)
                }
                .onChange(of: remote?.account?.id) { _, _ in showing = false }
        }
    }
    private var reportAction: ((String, String) async throws -> String)? {
        guard let remote, let owner = remote.account?.id, !remote.needsReauthentication else { return nil }
        return { reason, detail in
            guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
            return try await remote.reportContent(story: storyID, reason: reason, detail: detail)
        }
    }
}
