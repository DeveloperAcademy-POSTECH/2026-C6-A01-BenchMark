// Created by 이돈혁

import SwiftUI

struct PhotoTestView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                destination("콜라주", symbol: "photo.stack", detail: "사진 1~4장을 원본 비율 그대로 자동으로 배치해요.", manual: false)
                destination("레이아웃", symbol: "square.split.2x2", detail: "분할 틀을 고르고 각 칸에 사진을 넣어 직접 만들어요.", manual: true)
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("사진 테스트")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func destination(_ title: String, symbol: String, detail: String, manual: Bool) -> some View {
        NavigationLink { PhotoCollageEditor(manual: manual) } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(title, systemImage: symbol).font(.title3.bold())
                        Text(detail).font(.subheadline)
                    }
                } else {
                    HStack(spacing: 16) {
                        Image(systemName: symbol).font(.title).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.title3.bold())
                            Text(detail).font(.subheadline)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                }
            }
            .foregroundStyle(Color("OiGreen"))
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("OiLight"), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

#Preview { NavigationStack { PhotoTestView() } }
