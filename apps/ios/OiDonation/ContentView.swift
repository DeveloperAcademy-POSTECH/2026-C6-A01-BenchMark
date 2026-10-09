//
//  ContentView.swift
//  OiDonation
//
//  Created by jiwon hong on 10/8/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {

        ScrollView {
            VStack(spacing: 17) {
                // 상단 로고와 버튼
                HStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.gray.opacity(0.3))
                        .frame(width: 150, height: 44)

                    Spacer()

                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                }

                // 대표 이야기 배너
                RoundedRectangle(cornerRadius: 20)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 220)

                // 기부 내역
                RoundedRectangle(cornerRadius: 20)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 150)

                HStack {
                    // 기부금 영수증
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.gray.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)

                    }

                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .safeAreaInset(edge: .bottom) {

            HStack {
                // 홈, 내 기부, 벤치지도 영역
                RoundedRectangle(cornerRadius: 32)
                    .fill(.gray.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)

                // AR 진입 버튼
                Circle()
                    .fill(.gray.opacity(0.3))
                    .frame(width: 64, height: 64)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }

    }
}

#Preview {
    ContentView()
}
