//
//  ARGameFailureView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct ARGameFailureView: View {
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)

            Text("실패ㅠ")
                .font(.custom("KIMWILDgag-BOLD", size: 60, relativeTo: .largeTitle))
                .tracking(1.2)
                .foregroundStyle(.white)

            VStack {
                Spacer()

                Button(action: onRetry) {
                    Text("재도전")
                        .font(.custom("PearToucan-Regular", size: 30, relativeTo: .title))
                        .tracking(0.6)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .frame(width: 270, height: 70)
                .background(.white, in: Capsule())
                .accessibilityHint("AR 수집 게임을 처음부터 다시 시작합니다")
                .padding(.bottom, 68)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ARGameFailureView(onRetry: {})
}
