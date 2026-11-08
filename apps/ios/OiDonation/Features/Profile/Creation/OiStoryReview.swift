//
//  OiStoryReview.swift
//  OiDonation
//
//  Created by Jang Jihoon on 11/8/26.
//

import SwiftUI
import UIKit

struct OiStoryReviewIssue: Identifiable {
    let step: OiCreationStep
    let message: String
    var id: OiCreationStep { step }
}

struct OiStoryReview<StoryPhoto: View>: View {
    let draft: OiStoryDraft
    let customization: OiDraftCustomization
    let publicCard: MYCard
    let donorName: String
    let location: String?
    let photos: [OiEditingPhoto]
    let remote: OiRemoteStore
    let issues: [OiStoryReviewIssue]
    let error: String?
    let canSubmit: Bool
    let isSubmitting: Bool
    let onClose: () -> Void
    let onEdit: (OiCreationStep) -> Void
    let onSubmit: () -> Void
    let storyPhoto: (OiEditingPhoto, Bool) -> StoryPhoto

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: Artwork?
    @State private var portrait: UIImage?
    @State private var checkedPortrait = false
    @State private var showingCards = false

    private struct OutfitPhoto: Identifiable {
        let id: String
        let label: String
        let data: Data
    }

    private enum Artwork: Identifiable {
        case story(OiEditingPhoto, Int)
        case outfit(OutfitPhoto)
        case character

        var id: String {
            switch self {
            case .story(let photo, _): "story-" + photo.id
            case .outfit(let photo): "outfit-" + photo.id
            case .character: "character"
            }
        }
    }

    private var outfitPhotos: [OutfitPhoto] {
        guard let look = customization.wardrobe else { return [] }
        return OiPhotoSlot.allCases.filter { $0.supports(look) }.flatMap { slot in
            let layers = look.artwork.designs[slot.itemID(in: look)]?.layers ?? []
            return OiPhotoSide.allCases.flatMap { side in
                layers.filter { $0.side == side }.compactMap { layer -> OutfitPhoto? in
                    guard let data = look.artwork.sources[layer.source] else { return nil }
                    return OutfitPhoto(id: slot.id + layer.id, label: "\(slot.title(in: look)) · \(side.title)", data: data)
                }
            }
        }
    }

    private var characterName: String {
        draft.cucumberName.isEmpty ? "내 오이" : draft.cucumberName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("운영팀이 이야기와 사진을 승인하면 다른 사람의 지도와 현장 AR에 공개돼요.", systemImage: "checkmark.shield")
                        .font(CampusStyle.body(14)).foregroundStyle(CampusStyle.sectionGreen)
                        .padding(.horizontal, 4)
                    OiConnectionStatus(remote: remote)
                    if !issues.isEmpty { issuePanel }
                    storyPanel
                    characterPanel
                    cardPanel
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color("OiLight").ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { submitBar }
            .navigationTitle("공개 검토 전 확인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color("OiLight"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("돌아가기", systemImage: "chevron.left", action: onClose)
                        .labelStyle(.iconOnly).disabled(isSubmitting)
                        .accessibilityLabel("배치 미리보기로 돌아가기")
                }
            }
        }
        .tint(CampusStyle.sectionGreen)
        .interactiveDismissDisabled(isSubmitting)
        .task { restorePortrait() }
        .fullScreenCover(item: $selection) { item in
            switch item {
            case .story(let photo, let number):
                CampusArtworkOverlay(title: "이야기 사진 \(number)") { storyPhoto(photo, false) }
            case .outfit(let photo):
                CampusArtworkOverlay(title: photo.label) { outfitImage(photo, mode: .fit) }
            case .character:
                CampusArtworkOverlay(title: characterName) {
                    if let look = customization.wardrobe {
                        OiWardrobePreview(look: look)
                            .frame(height: 410)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    } else {
                        OiCreationCharacterImage(asset: draft.cucumberAsset)
                    }
                }
            }
        }
    }

    private var storyPanel: some View {
        panel {
            sectionHeader("이야기", symbol: "book.closed", edit: .story)
            Text(draft.title.isEmpty ? "제목을 입력해 주세요" : draft.title)
                .font(CampusStyle.characterTitle(26)).foregroundStyle(Color("OiDark"))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            let tags = [draft.theme, draft.emotion].filter { !$0.isEmpty }
            if !tags.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { tagChips(tags) }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 6) { tagChips(tags) }
                }
            }
            Text(draft.body.isEmpty ? "작성한 이야기가 여기에 표시돼요." : draft.body)
                .font(CampusStyle.body(16)).lineSpacing(5)
                .foregroundStyle(draft.body.isEmpty ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.top, 4)
            sectionHeader("이야기 사진 \(photos.count)장", symbol: "photo.on.rectangle", edit: .photos)
            if photos.isEmpty {
                Text("아직 첨부한 사진이 없어요.").font(CampusStyle.body(14)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns(min(3, photos.count)), spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button { selection = .story(photo, index + 1) } label: {
                            thumbnail(aspect: photos.count == 1 ? 1.65 : 1) { storyPhoto(photo, true) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("이야기 사진 \(index + 1) 크게 보기")
                        .accessibilityIdentifier("oi.review.storyPhoto.\(index + 1)")
                        .disabled(isSubmitting)
                    }
                }
            }
        }
    }

    private var characterPanel: some View {
        panel {
            sectionHeader("내가 꾸민 오이", symbol: "leaf", edit: .cucumber)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            layout {
                Button { selection = .character } label: {
                    characterArtwork
                        .frame(width: 112, height: 142)
                        .background(Color("OiSoft"), in: RoundedRectangle(cornerRadius: 16))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(characterName) 크게 보기")
                .accessibilityIdentifier("oi.review.character")
                .disabled(isSubmitting)
                VStack(alignment: .leading, spacing: 8) {
                    Text(characterName).font(CampusStyle.characterTitle(21)).foregroundStyle(Color("OiDark"))
                    if let look = customization.wardrobe {
                        Text(look.title).font(CampusStyle.body(13)).foregroundStyle(.secondary)
                    }
                    if let location {
                        Label(location, systemImage: "mappin").font(CampusStyle.body(13))
                    }
                    if let height = draft.heightMeters {
                        Label("현장 AR 높이 \(height * 100, specifier: "%.0f")cm", systemImage: "ruler")
                            .font(CampusStyle.body(13))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            let applied = outfitPhotos
            if !applied.isEmpty {
                Divider().padding(.top, 4)
                Text("의상에 사용한 사진").font(CampusStyle.semibold(15)).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns(typeSize.isAccessibilitySize ? 2 : 3), alignment: .leading, spacing: 12) {
                    ForEach(applied) { photo in
                        Button { selection = .outfit(photo) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                thumbnail(aspect: 1) { outfitImage(photo, mode: .fill) }
                                Text(photo.label).font(CampusStyle.body(12)).foregroundStyle(.secondary)
                            }.frame(maxHeight: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(photo.label) 사진 크게 보기")
                        .disabled(isSubmitting)
                    }
                }
            }
            Text("꾸민 외형과 의상 사진은 이 기기의 내 오이에 표시돼요.")
                .font(CampusStyle.body(12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var characterArtwork: some View {
        if let portrait {
            Image(uiImage: portrait).resizable().scaledToFit().padding(4)
        } else if let look = customization.wardrobe {
            if !checkedPortrait { ProgressView() }
            else if selection?.id != Artwork.character.id {
                OiWardrobePreview(look: look, controls: false).allowsHitTesting(false)
            }
        } else {
            OiCreationCharacterImage(asset: draft.cucumberAsset).padding(8)
        }
    }

    private var cardPanel: some View {
        panel {
            DisclosureGroup(isExpanded: $showingCards) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .center, spacing: 20))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    card("내가 꾸민 카드") {
                        OiDraftCardPreview(draft: draft, customization: customization, donorName: donorName)
                    }
                    card("공개용 카드") { MYCardArtwork(card: publicCard) }
                }.padding(.top, 14)
            } label: {
                Label("카드 미리보기", systemImage: "rectangle.on.rectangle")
                    .font(CampusStyle.semibold(16)).foregroundStyle(Color("OiDark"))
                    .frame(minHeight: 32)
            }
        }
    }

    private var issuePanel: some View {
        panel {
            Label("확인이 필요한 항목", systemImage: "exclamationmark.circle")
                .font(CampusStyle.semibold(16)).accessibilityAddTraits(.isHeader)
            ForEach(issues) { issue in
                Button { onEdit(issue.step) } label: {
                    HStack {
                        Text(issue.message).font(CampusStyle.body(14)).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(CampusStyle.sectionGreen).disabled(isSubmitting)
            }
        }
    }

    private var submitBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.red)
            }
            OiCreationNextButton(title: isSubmitting ? "공개 검토 요청 중…" : "공개 검토 요청하기",
                                 enabled: canSubmit && !isSubmitting, action: onSubmit)
                .accessibilityIdentifier("oi.story.confirmSubmit")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { Color(.systemBackground).ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) { Divider() }
    }

    private func sectionHeader(_ title: String, symbol: String, edit step: OiCreationStep) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(CampusStyle.sectionGreen).accessibilityHidden(true)
            Text(title).font(CampusStyle.semibold(16)).foregroundStyle(Color("OiDark"))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button("수정") { onEdit(step) }
                .font(CampusStyle.medium(13)).buttonStyle(.plain).foregroundStyle(CampusStyle.sectionGreen)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .accessibilityLabel("\(title) 수정").disabled(isSubmitting)
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color("OiBorder").opacity(0.55)) }
    }

    private func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8, alignment: .top), count: count)
    }

    private func thumbnail<Content: View>(aspect: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let image = content()
        return Color("OiSoft").aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    image.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func outfitImage(_ photo: OutfitPhoto, mode: ContentMode) -> some View {
        Group {
            if let image = UIImage(data: photo.data) { Image(uiImage: image).resizable().aspectRatio(contentMode: mode) }
            else { Image(systemName: "photo").foregroundStyle(.secondary).accessibilityLabel("사진을 불러올 수 없어요") }
        }
    }

    private func tagChips(_ tags: [String]) -> some View {
        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
            Text(tag).font(CampusStyle.medium(12)).foregroundStyle(CampusStyle.sectionGreen)
                .padding(.horizontal, 10).padding(.vertical, 5).background(Color("OiSoft"), in: Capsule())
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder artwork: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title).font(CampusStyle.medium(13)).multilineTextAlignment(.center)
            artwork().aspectRatio(362 / 502, contentMode: .fit)
        }.frame(maxWidth: 240)
    }

    private func restorePortrait() {
        if let look = customization.wardrobe, let card = customization.card, let bytes = card.portraitPNG {
            let angle = card.characterOrientation ?? OiCardOrientation()
            let key = OiCardPortrait.key(for: look) + "-angle-" + angle.cacheIdentity
            if card.portraitKey == key { portrait = UIImage(data: bytes) }
        }
        checkedPortrait = true
    }
}
