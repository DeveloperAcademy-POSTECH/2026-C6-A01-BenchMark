//
//  OiConnectedDonationPicker.swift
//  OiDonation
//
//  Created by Jiwon Hong on 11/16/26.
//

import SwiftUI

/// Figma `6183:2707` (이어진 기부 대상 선택): the five stories opened most recently, one of which this donation continues from.
struct OiConnectedDonationPicker: View {
    let stories: [CampusStory]
    let onCancel: () -> Void
    let onDone: (String) -> Void
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if stories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(stories) { story in
                            Button { selection = story.id } label: { card(story) }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selection == story.id ? .isSelected : [])
                                .accessibilityIdentifier("oi.connected.story.\(story.id)")
                        }
                    }.padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 20)
                }.scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("최근 본 오이 \(OiRecentStories.pickerLimit)개 중 1개를 대상으로 선택할 수 있습니다")
                .font(CampusStyle.body(14)).tracking(0.28).foregroundStyle(Color(oiRGB: 0xFF6666))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 44).padding(.bottom, 3)
        }
        .preferredColorScheme(.light)
    }

    /// 취소 and 완료 flank the title, 20pt from the edges.
    private var header: some View {
        ZStack {
            Text("이어질 기부 선택").font(CampusStyle.medium(20)).tracking(0.4).foregroundStyle(.black)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onCancel) {
                    Text("취소").font(.custom("Paperlogy-3Light", size: 20, relativeTo: .title3)).tracking(0.4)
                        .foregroundStyle(Color(oiRGB: 0x6C6C6C)).frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("oi.connected.cancel")
                Spacer(minLength: 0)
                Button { if let selection { onDone(selection) } } label: {
                    Text("완료").font(CampusStyle.medium(20)).tracking(0.4)
                        .foregroundStyle(selection == nil ? Color(oiRGB: 0x6C6C6C).opacity(0.4) : .black)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                }.disabled(selection == nil).accessibilityIdentifier("oi.connected.done")
            }
        }.padding(.horizontal, 20).padding(.top, 8)
    }

    private func card(_ story: CampusStory) -> some View {
        let isSelected = selection == story.id
        return OiCucumberCard(name: story.title, tags: story.tags, donor: story.donor, title: story.storyTitle,
                              outline: isSelected ? Color(oiRGB: 0x849644) : Color(oiRGB: 0xD3DBC4),
                              outlineWidth: isSelected ? 2 : 1, shadowOpacity: 0) {
            CampusCucumberPortrait(story: story)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("최근에 본 이야기가 없어요").font(CampusStyle.medium(18)).foregroundStyle(.black)
            Text("지도에서 오이 이야기를 열어 보면 여기에 나타나요").font(CampusStyle.body(14)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine).accessibilityIdentifier("oi.connected.empty")
    }
}
