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
    /// The trimmed cucumber prepared before this screen appears, so it never pops in afterwards.
    var initialFigure: UIImage? = nil
    @State private var showingBack = false
    /// 공유 opens the system share sheet with both card faces; its own 이미지 저장 action saves them to Photos.
    @State private var sharedCard: SharedCard?
    @State private var preparingShare = false
    @State private var shareError: String?
    private struct SharedCard: Identifiable { let id = UUID(); let images: [UIImage] }
    /// The card portrait keeps transparent margins; trim them so the figure fills Figma's 269pt height.
    @State private var figure: UIImage?

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
            HStack(spacing: 8) {
                // Icon-only share button in the system's default style, left of 완료.
                Button(action: shareCard) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(minWidth: 22, minHeight: 22)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .disabled(preparingShare)
                .accessibilityLabel("공유")
                .accessibilityIdentifier("oi.creation.completion.share")
                Button(action: onDone) {
                    Text("완료").font(CampusStyle.body(16)).tracking(0.32)
                        .frame(height: 20)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color("OiBorder"), in: Capsule())
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(OiCreationPressStyle()).foregroundStyle(.black)
                .accessibilityIdentifier("oi.creation.completion.done")
            }
            .padding(.trailing, 20)
            .padding(.top, -8)
        }
        .background(Color(oiRGB: 0xF0F0F0).ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .sheet(item: $sharedCard) { OiCardShareSheet(images: $0.images) }
        .alert("카드를 공유할 수 없어요", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(shareError ?? "") }
    }

    /// Renders the front and back and opens the share sheet straight away (no extra picker sheet).
    private func shareCard() {
        guard !preparingShare else { return }
        preparingShare = true
        defer { preparingShare = false }
        do {
            let card = try OiDraftCardPreview(draft: draft, customization: customization, donorName: donorName)
                .publication(colorScheme: .light)
            let images = try OiCardExportImages(card)
            sharedCard = SharedCard(images: [images.front] + (images.back.map { [$0] } ?? []))
        } catch { shareError = error.localizedDescription }
    }

    /// Figma: cucumber frame 34–173pt × 76–353pt with the visible figure at 81–350pt
    /// (center x 97pt), and the white info block at 158pt × 192pt laid under it.
    private var summary: some View {
        ZStack(alignment: .topLeading) {
            info.frame(width: 209).offset(x: 124, y: 116)
            // Fit Figma's 269pt figure height; wide costumes may use up to 170pt, centered on x 97pt.
            cucumber
                .frame(width: 170, height: 269, alignment: .bottom)
                .offset(x: -22.5, y: 5)
        }
        .frame(width: 333, height: 277, alignment: .topLeading)
        .task(id: figureSourceKey) {
            // The editor already prepared the first figure; only a changed source needs trimming again.
            if figure == nil, initialFigure != nil { return }
            figure = await Self.figureImage(draft: draft, customization: customization)
        }
    }

    private var figureSourceKey: String {
        "\(customization.showsCharacter)/\(design.portraitKey ?? "")/\(design.portraitPNG?.count ?? 0)/\(draft.cucumberAsset)"
    }

    /// The card portrait with its transparent margins trimmed, ready to draw at Figma's 269pt height.
    static func figureImage(draft: OiStoryDraft, customization: OiDraftCustomization) async -> UIImage? {
        let design = customization.card ?? OiCardDesign()
        let data = design.portraitPNG
        let asset = draft.cucumberAsset == "OiCats" ? "OiCatsPortrait" : draft.cucumberAsset
        guard let source = data.flatMap(UIImage.init(data:)) ?? UIImage(named: asset) else { return nil }
        return await Task.detached(priority: .userInitiated) { OiOpaqueImageTrim.trimmed(source) }.value
    }

    @ViewBuilder private var cucumber: some View {
        if let figure = figure ?? initialFigure {
            Image(uiImage: figure).resizable().scaledToFit().accessibilityLabel("내가 꾸민 오이")
        } else {
            Color.clear
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
