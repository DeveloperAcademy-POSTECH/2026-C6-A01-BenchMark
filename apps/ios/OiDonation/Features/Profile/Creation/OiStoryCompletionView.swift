//
//  OiStoryCompletionView.swift
//  OiDonation
//
//  Created by Jiwon Hong on 11/16/26.
//

import SwiftUI

/// Figma `5887:10243` (접수 완료 뷰): shown after STEP 4 `완료` once the draft is
/// saved on this device. It only summarizes the draft; nothing is sent for review here.
struct OiStoryCompletionView: View {
    let draft: OiStoryDraft
    let customization: OiDraftCustomization
    let donorName: String
    let location: String
    let onDone: () -> Void
    @State private var showingBack = false

    private var design: OiCardDesign { customization.card ?? OiCardDesign() }
    private var tags: [String] { [draft.emotion, draft.theme].filter { !$0.isEmpty } }
    private var author: String {
        OiPostcardAuthor.text(mode: design.postcardBackground?.authorMode, name: donorName,
                              academic: design.postcardAcademicAuthor ?? "")
    }
    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: design.postcardDate ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            OiFlippablePostcard(showingBack: $showingBack) {
                OiDraftCardPreview(draft: draft, customization: customization, donorName: donorName)
                    .frame(width: 362, height: 502)
            } back: {
                OiDraftCardPreview(draft: draft, customization: customization, donorName: donorName, showingBack: true)
                    .frame(width: 362, height: 502)
            }
            .frame(maxWidth: 292)
            .padding(.top, 37)
            .layoutPriority(-1)
            Text("탭하거나 옆으로 밀어서 뒤집기")
                .font(CampusStyle.body(16)).tracking(0.32)
                .foregroundStyle(Color(oiRGB: 0x9C9C9C))
                .padding(.top, 13)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button(action: onDone) {
                Text("완료").font(CampusStyle.body(16)).tracking(0.32)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Color("OiBorder"), in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(OiCreationPressStyle()).foregroundStyle(.black)
            .padding(.trailing, 20)
            .padding(.top, -8)
            .accessibilityIdentifier("oi.creation.completion.done")
        }
        .background(Color(oiRGB: 0xF0F0F0).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    /// Cucumber (139×277) with the white info block overlapping its right edge.
    private var summary: some View {
        ZStack(alignment: .topLeading) {
            cucumber.frame(width: 139, height: 277)
            info.frame(width: 209).offset(x: 124, y: 116)
        }
        .frame(width: 333, height: 277, alignment: .topLeading)
    }

    @ViewBuilder private var cucumber: some View {
        if customization.showsCharacter, let data = design.portraitPNG, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("내가 꾸민 오이")
        } else {
            OiCreationCharacterImage(asset: draft.cucumberAsset)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(draft.cucumberName.isEmpty ? "나의 오이" : draft.cucumberName)
                    .font(CampusStyle.characterTitle(26)).tracking(0.52)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#" + tag).font(CampusStyle.body(15)).tracking(0.3)
                        }
                    }
                    .foregroundStyle(Color(oiRGB: 0xA15C03))
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach([author, location, dateLabel].filter { !$0.isEmpty }, id: \.self) { line in
                    Text("| " + line).font(CampusStyle.body(11)).tracking(0.22)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(.black)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .combine)
    }
}
