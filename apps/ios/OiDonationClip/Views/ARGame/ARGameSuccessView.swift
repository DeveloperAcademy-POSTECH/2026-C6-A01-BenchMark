//
//  ARGameSuccessView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGameSuccessView: View {
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)

            Text("성공!")
                .font(.custom("KIMWILDgag-BOLD", size: 60, relativeTo: .largeTitle))
                .tracking(1.2)
                .foregroundStyle(.white)
        }
        .ignoresSafeArea()
        .task {
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

#Preview {
    ARGameSuccessView(onFinished: {})
}
