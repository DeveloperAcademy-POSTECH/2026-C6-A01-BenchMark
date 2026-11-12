//
//  ARPostcardResultView.swift
//  OiDonationClip
//
//  Created by Jiwon Hong on 11/9/26.
//

#if DEBUG
import SwiftUI

/// Debug sample postcard. The artwork already contains the donor story, so the text below is
/// only used for VoiceOver. It is not a published story and is not saved to any collection.
struct ARPostcardSampleContent {
    let imageName: String
    let title: String
    let from: String
    let to: String
    let story: String

    static let sample = ARPostcardSampleContent(
        imageName: "ARPostcardSample",
        title: "그때는 몰랐던, 소중한 순간들",
        from: "24학번 경영학과 홍지원",
        to: "경영학과 24 동기들에게",
        story: """
        시험 기간에 공부가 지겨워질 때면 동기들과 청년광장에 앉아 떡볶이와 맥주를 즐기곤 했습니다. \
        수업을 마치고 돌아가는 길에는 청년광장에 노을이 지는 모습을 한참 바라보기도 했고요. \
        봄과 가을이면 사람들로 북적이는 광장에서 동기들과 웃고 떠들던 기억도 납니다. \
        돌이켜보면 청년광장에서 참 많은 시간을 보냈던 것 같습니다. \
        당시에는 별 생각 없이 지나쳤던 순간들인데, 졸업하고 나니 그런 평범한 일상이 가끔 그리워지곤 합니다. \
        언젠가 다시 청년광장에 앉아 그때처럼 친구들과 시간을 보내고 싶습니다.
        """
    )
}

struct ARPostcardResultView: View {
    let postcard: ARPostcardSampleContent

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("엽서를 완성했어요")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    Image(postcard.imageName)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .accessibilityElement()
                        .accessibilityLabel("엽서, \(postcard.title)")
                        .accessibilityValue("보낸 사람 \(postcard.from). 받는 사람 \(postcard.to). \(postcard.story)")
                        .accessibilityIdentifier("appclip.postcardPrototype.postcard")

                    Text("개발용 샘플 엽서예요. 도감이나 이 기기에 저장되지 않아요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color(.secondarySystemBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("appclip.postcardPrototype.close")
                }
            }
        }
    }
}

#Preview {
    ARPostcardResultView(postcard: .sample)
}
#endif
