//
//  MYFarmerCustomizationView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/5/26.
//

import SwiftUI

struct MYFarmerCustomizationView: View {
    private nonisolated enum ScrollTarget: Hashable, Sendable { case categories }

    var remote: OiRemoteStore?
    @State private var initial: OiFarmerOutfit
    @State private var drafts: [String: OiFarmerOutfit]
    @State private var character: String
    @State private var category = MYFarmerSlot.top
    @State private var wardrobeScrollPosition = ScrollPosition(idType: ScrollTarget.self)
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var pendingSaveID: UUID?
    @State private var pendingSave: (owner: UUID, outfit: OiFarmerOutfit)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(remote: OiRemoteStore?) {
        self.remote = remote
        let outfit = remote?.farmerOutfit ?? .legacy(MYFarmerAppearanceStore.read(ownerID: remote?.account?.id))
        _initial = State(initialValue: outfit)
        _drafts = State(initialValue: [outfit.character: outfit])
        _character = State(initialValue: outfit.character)
    }

    private var selection: OiFarmerOutfit { drafts[character] ?? OiFarmerOutfit(character: character, slots: [:]) }

    var body: some View {
        Group {
            switch MYFarmerWardrobe.loaded {
            case .success(let wardrobe):
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing: 16) {
                            header(wardrobe)
                            preview(wardrobe)
                            characterSelector
                            categorySelector.id(ScrollTarget.categories)
                            itemGrid(wardrobe)
                            notices
                        }.scrollTargetLayout()
                    }
                    .scrollPosition($wardrobeScrollPosition)
                } else {
                    VStack(spacing: 0) {
                        header(wardrobe).padding(.top, 9)
                        preview(wardrobe).padding(.top, 18)
                        characterSelector
                        categorySelector
                        ScrollView {
                            itemGrid(wardrobe).padding(.top, 5)
                            notices
                        }
                        .scrollIndicators(.hidden)
                        .scrollPosition($wardrobeScrollPosition)
                    }
                }
            case .failure:
                ContentUnavailableView("옷장을 불러올 수 없어요", systemImage: "tshirt", description: Text("앱을 다시 실행하거나 최신 버전을 확인해 주세요."))
            }
        }
        .background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(isSaving)
        .accessibilityAction(.escape) { if !isSaving { dismiss() } }
        .onChange(of: category) { _, _ in
            if dynamicTypeSize.isAccessibilitySize {
                wardrobeScrollPosition.scrollTo(id: ScrollTarget.categories, anchor: .top)
            } else {
                wardrobeScrollPosition.scrollTo(edge: .top)
            }
        }
        .task(id: pendingSaveID) {
            guard pendingSaveID != nil, let request = pendingSave, let remote else { return }
            let saved = await remote.saveFarmerOutfit(request.outfit)
            guard !Task.isCancelled else { return }
            isSaving = false; pendingSave = nil
            guard remote.account?.id == request.owner else { return }
            if saved { dismiss() }
            else { saveError = remote.error ?? "농부 모습을 저장하지 못했어요. 다시 시도해 주세요." }
        }
        .onChange(of: remote?.account?.id) { _, _ in resetFromAccount() }
        .onChange(of: remote?.farmerOutfit) { _, value in
            guard let value else { return }
            let pristine = drafts.count == 1 && selection == initial
            initial = value
            if pristine { character = value.character; drafts = [value.character: value] }
        }
    }

    private func header(_ wardrobe: MYFarmerWardrobe) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { saveButton(wardrobe); Spacer(); closeButton }
                    resetButton
                }
            } else {
                HStack(spacing: 16) {
                    saveButton(wardrobe)
                    resetButton
                    Spacer(minLength: 0)
                    closeButton
                }
            }
        }.padding(.horizontal, 20)
    }

    private func saveButton(_ wardrobe: MYFarmerWardrobe) -> some View {
        Button {
            guard let remote, let owner = remote.account?.id else { return }
            isSaving = true; saveError = nil
            pendingSave = (owner: owner, outfit: selection)
            pendingSaveID = UUID()
        } label: {
            Group {
                if isSaving { ProgressView().tint(.white) }
                else { Text("저장").font(CampusStyle.medium(20)).tracking(0.4) }
            }.foregroundStyle(Color(red: 241 / 255, green: 244 / 255, blue: 236 / 255))
                .padding(.horizontal, 20).frame(minHeight: 40)
                .background(CampusStyle.green, in: Capsule())
        }.buttonStyle(.plain)
            .disabled(isSaving || remote?.isBusy == true || remote?.needsReauthentication == true ||
                      remote?.account == nil || remote?.isFarmerOutfitAvailable != true || !wardrobe.validates(selection))
            .accessibilityIdentifier("my.farmer.save")
    }

    private var resetButton: some View {
        Button {
            character = initial.character; drafts = [initial.character: initial]; saveError = nil
        } label: {
            Text("되돌리기").font(CampusStyle.medium(14)).tracking(0.28).underline()
                .foregroundStyle(Color(white: 107 / 255)).frame(minHeight: 44)
        }.buttonStyle(.plain).disabled(isSaving).accessibilityIdentifier("my.farmer.reset")
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 19)).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.black).disabled(isSaving).accessibilityLabel("저장하지 않고 닫기")
    }

    private func preview(_ wardrobe: MYFarmerWardrobe) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    MYFarmerLayeredArtwork(outfit: selection, wardrobe: wardrobe).frame(height: 220)
                    ForEach([MYFarmerSlot.hat, .accessory, .top, .bottom, .shoes, .set]) { slot in
                        HStack { Text(slot.title); Spacer(); Text(itemName(slot, wardrobe)) }
                            .font(CampusStyle.medium(16))
                    }
                }.padding(.horizontal, 20)
            } else {
                GeometryReader { geometry in
                    MYFarmerLayeredArtwork(outfit: selection, wardrobe: wardrobe)
                        .frame(width: 200, height: 277)
                        .position(x: geometry.size.width / 2 - 3, y: 138.5)
                    callout(.hat, wardrobe).position(x: geometry.size.width * 0.213, y: 27)
                    callout(.accessory, wardrobe).position(x: geometry.size.width * 0.213, y: 96)
                    callout(.top, wardrobe).position(x: geometry.size.width * 0.81, y: 102)
                    callout(.bottom, wardrobe).position(x: geometry.size.width * 0.81, y: 171)
                    callout(.shoes, wardrobe).position(x: geometry.size.width * 0.81, y: 244)
                }.frame(height: 277)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(character == "kyu" ? "큐" : "컴버") 착용 미리보기")
        .accessibilityValue([MYFarmerSlot.hat, .accessory, .top, .bottom, .shoes, .set]
            .map { "\($0.title): \(itemName($0, wardrobe))" }.joined(separator: ", "))
    }

    private func callout(_ slot: MYFarmerSlot, _ wardrobe: MYFarmerWardrobe) -> some View {
        VStack(spacing: 0) {
            Text(slot.title).font(.custom("Paperlogy-7Bold", size: 10, relativeTo: .caption2))
                .tracking(0.2).foregroundStyle(CampusStyle.green).frame(minHeight: 15)
            Text(itemName(slot, wardrobe)).font(CampusStyle.medium(12)).tracking(0.24)
                .multilineTextAlignment(.center).lineLimit(2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(white: 239 / 255), in: Capsule())
        }.frame(maxWidth: 105)
    }

    private func itemName(_ slot: MYFarmerSlot, _ wardrobe: MYFarmerWardrobe) -> String {
        if slot == .set, selection.slots["set"] == "legacy-classic" { return "농부 세트" }
        if slot == .set, selection.slots["set"] == "legacy-casual" { return "큐 기본 세트" }
        return wardrobe.item(selection.slots[slot.rawValue])?.name ?? "-"
    }

    private var characterSelector: some View {
        HStack {
            HStack(spacing: 0) {
                ForEach(["kyu", "cumber"], id: \.self) { value in
                    Button { character = value } label: {
                        Text(value == "kyu" ? "큐" : "컴버").font(CampusStyle.medium(12)).tracking(0.24)
                            .foregroundStyle(value == character ? CampusStyle.green : CampusStyle.sectionGreen)
                            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
                            .frame(minWidth: 37, minHeight: 26)
                            .background(value == character ? Color.white : .clear, in: Capsule())
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(isSaving)
                        .accessibilityAddTraits(value == character ? .isSelected : [])
                        .accessibilityIdentifier("my.farmer.character.\(value)")
                }
            }.padding(2).background(Color(red: 211 / 255, green: 219 / 255, blue: 196 / 255), in: Capsule())
                .frame(minHeight: 44)
            Spacer()
        }.padding(.horizontal, 20)
    }

    private var categorySelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                ForEach(MYFarmerSlot.allCases) { slot in
                    Button { category = slot } label: {
                        Text(slot.title)
                            .font(.custom(category == slot ? "Paperlogy-7Bold" : "Paperlogy-5Medium", size: 16, relativeTo: .body))
                            .tracking(0.32).foregroundStyle(category == slot ? CampusStyle.green : Color(white: 113 / 255))
                            .padding(.bottom, 5).padding(.top, 8).frame(minHeight: 44)
                            .overlay(alignment: .bottom) {
                                if category == slot { Rectangle().fill(CampusStyle.green).frame(height: 2) }
                            }
                    }.buttonStyle(.plain).disabled(!slot.isAvailable || isSaving)
                        .accessibilityAddTraits(category == slot ? .isSelected : [])
                        .accessibilityHint(slot.isAvailable ? "선택할 의상을 표시합니다" : "준비 중입니다")
                        .accessibilityIdentifier("my.farmer.category.\(slot.rawValue)")
                }
            }.padding(.horizontal, 20)
        }.scrollIndicators(.hidden)
    }

    private func itemGrid(_ wardrobe: MYFarmerWardrobe) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.adaptive(minimum: 150), spacing: 16)]
            : Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(wardrobe.items(character: character, slot: category)) { item in
                Button { drafts[character] = selection.selecting(item) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.aspectRatio(item.thumbnail.width / max(1, item.thumbnail.height - 28), contentMode: .fit)
                            .overlay {
                                GeometryReader { geometry in
                                    MYFarmerCanvasArtwork(canvas: item.thumbnail)
                                        .scaleEffect(geometry.size.width / item.thumbnail.width, anchor: .topLeading)
                                }
                            }.clipped()
                        Text("무료")
                            .font(CampusStyle.medium(12)).tracking(0.24)
                            .padding(.horizontal, 11).padding(.bottom, 8).frame(minHeight: 28)
                    }.foregroundStyle(.black)
                        .background(Color(white: 249 / 255), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selection.slots[item.slot.rawValue] == item.id ? CampusStyle.green : .clear, lineWidth: 2)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(isSaving)
                    .accessibilityLabel(item.name)
                    .accessibilityValue("무료")
                    .accessibilityAddTraits(selection.slots[item.slot.rawValue] == item.id ? .isSelected : [])
                    .accessibilityIdentifier("my.farmer.item.\(item.id)")
            }
        }.padding(.horizontal, 20)
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let remote { OiConnectionStatus(remote: remote, showsInitialProgress: false) }
            if let saveError { Text(saveError).foregroundStyle(.red).accessibilityIdentifier("my.farmer.saveError") }
            if remote?.account == nil { Text("로그인하면 농부 모습을 계정에 저장할 수 있어요.") }
            else if remote?.isFarmerOutfitAvailable != true { Text("농부 모습 저장을 준비 중이에요. 잠시 후 다시 시도해 주세요.") }
        }.font(CampusStyle.body(14)).padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resetFromAccount() {
        let outfit = remote?.farmerOutfit ?? .legacy(MYFarmerAppearanceStore.read(ownerID: remote?.account?.id))
        initial = outfit; drafts = [outfit.character: outfit]; character = outfit.character; saveError = nil
        pendingSaveID = nil; pendingSave = nil; isSaving = false
    }
}

#Preview("Farmer · Reference", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack { MYFarmerCustomizationView(remote: nil) }
}
#Preview("Farmer · Small", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack { MYFarmerCustomizationView(remote: nil) }
}
#Preview("Farmer · Large", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack { MYFarmerCustomizationView(remote: nil) }
}
