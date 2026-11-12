import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum OiCardTab: String, CaseIterable {
    case content = "내용", background = "배경", pattern = "패턴", size = "오이 배치"
}

struct OiCardCustomizationStep: View {
    @Binding var draft: OiStoryDraft
    @Binding var customization: OiDraftCustomization
    var donorName = ""
    var canContinue = true
    var isFinished = false
    var onContinue: (() -> Void)?
    var onSizeEditingChanged: ((Bool) -> Void)? = nil
    @State private var showingBack = false
    @State private var tab: OiCardTab = .content
    @State private var portrait: UIImage?
    @State private var portraitFailed = false
    @State private var captureAttempt = 0
    @State private var wardrobeKey: String?
    @State private var orientation = OiCardOrientation()
    private var portraitKey: String? {
        wardrobeKey.map { $0 + "-angle-" + orientation.cacheIdentity }
    }
    @State private var showingPhotoEditor = false
    @State private var nameInput = ""
    @FocusState private var editingName: Bool
    private var design: OiCardDesign { customization.card ?? OiCardDesign() }
    private var needsPortrait: Bool { customization.showsCharacter && portraitKey != nil && (design.portraitKey != portraitKey || design.portraitPNG == nil) }

    private var isSizeEditing: Bool { tab == .size && !isFinished }

    var body: some View {
        GeometryReader { geometry in
            let previewHeight = isSizeEditing
                ? min(268.0, max(64.0, geometry.size.height * 0.38))
                : min(308.0, max(205.0, geometry.size.height * 0.47))
            VStack(spacing: 0) {
                Picker("엽서 면", selection: $showingBack) {
                    Text("앞면").tag(false)
                    Text("뒷면").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal, 60).padding(.top, 6)
                    .accessibilityIdentifier("oi.postcard.side")
                preview(height: previewHeight).padding(.horizontal, 20)
                    .padding(.top, isSizeEditing ? 8 : 14).padding(.bottom, isSizeEditing ? 12 : 24)
                if isFinished {
                    ScrollView {
                        VStack(spacing: 16) {
                            Text("카드 꾸미기를 마쳤어요").font(CampusStyle.semibold(20))
                            Text("다음을 눌러 이야기와 카드를 확인해 주세요.").font(CampusStyle.body(14))
                            storageDetails
                        }.padding(20)
                    }
                } else {
                    tabs.padding(.horizontal, 20).padding(.bottom, 8)
                    if isSizeEditing {
                        GeometryReader { editor in
                            // Fit the card's real aspect ratio into the remaining space.
                            // No ScrollView owns gestures over the character editor.
                            let height = max(1, min(editor.size.height - 56,
                                                    (editor.size.width - 40) * 436 / 296))
                            placementEditor(height: height)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .background(Color("OiBorder").opacity(0.75).ignoresSafeArea(edges: .bottom))
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                controls
                                storageDetails
                            }.padding(.horizontal, 20).padding(.bottom, 20)
                        }.scrollDismissesKeyboard(.interactively)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPhotoEditor) {
            OiCardBackgroundPhotoEditor(design: cardBinding)
                .presentationDetents([.height(410)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(35)
                .presentationBackground(Color("OiLight"))
        }
        .onAppear { prepareBackground(); if design.postcardDate == nil { change { $0.postcardDate = Date() } }; refreshPortrait(); nameInput = baseName; onSizeEditingChanged?(isSizeEditing) }
        .onChange(of: customization.wardrobe) { _, _ in refreshPortrait() }
        .onChange(of: tab) { _, value in saveOrientation(); if value == .size { showingBack = false } }
        .onChange(of: isSizeEditing) { _, editing in onSizeEditingChanged?(editing) }
        .onDisappear { saveOrientation(); onSizeEditingChanged?(false) }
        .onChange(of: editingName) { _, focused in if !focused { commitName() } }
        .onChange(of: isFinished) { _, finished in if finished { editingName = false; commitName() } }
    }

    private func preview(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            OiDraftCardPreview(draft: draft, customization: customization, donorName: donorName, portrait: portrait, showingBack: showingBack)
                .frame(width: height * 362 / 502, height: height)
                .overlay {
                    if needsPortrait, (tab != .size || isFinished), let look = customization.wardrobe {
                        OiCardPortraitCapture(look: look, cacheKey: portraitKey ?? "", orientation: orientation,
                                              onCapture: acceptPortrait, onFailure: { portraitFailed = true })
                            .id(captureAttempt)
                            .aspectRatio(332 / 472, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .opacity(0.001).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .top) {
                    if needsPortrait && tab != .size {
                        Group {
                            if portraitFailed {
                                Button("오이 이미지 다시 만들기") { portraitFailed = false; captureAttempt += 1 }
                            } else { ProgressView("오이를 엽서에 담는 중") }
                        }.font(CampusStyle.body(11)).padding(8).background(.regularMaterial, in: Capsule())
                    }
                }
            HStack(alignment: .bottom) {
                VStack(spacing: 3) {
                    Text("오이").font(CampusStyle.medium(13))
                    VStack(spacing: 0) {
                        visibilityButton("가림", visible: false)
                        visibilityButton("보임", visible: true)
                    }.padding(2).background(Color(white: 0.85), in: Capsule())
                }
                Spacer()
                if let onContinue {
                    Button { editingName = false; commitName(); onContinue() } label: {
                        Text(isFinished ? "다시 꾸미기" : "완료").underline()
                            .font(CampusStyle.medium(16)).padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Color("OiBorder"), in: Capsule())
                    }.buttonStyle(OiCreationPressStyle()).foregroundStyle(.black)
                        .disabled(!canContinue || needsPortrait)
                        .accessibilityIdentifier("oi.customization.done")
                }
            }
        }.frame(maxWidth: .infinity).frame(height: height)
    }
    private func visibilityButton(_ title: String, visible: Bool) -> some View {
        Button { customization.showsCharacter = visible } label: {
            Text(title).font(CampusStyle.body(10)).frame(width: 30, height: 42)
                .background(customization.showsCharacter == visible ? Color.white : .clear, in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(.black)
            .accessibilityLabel("카드 오이 \(title)")
            .accessibilityAddTraits(customization.showsCharacter == visible ? .isSelected : [])
    }
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(OiCardTab.allCases, id: \.self) { item in
                Button { editingName = false; tab = item } label: {
                    Text(item.rawValue).font(tab == item ? CampusStyle.semibold(14) : CampusStyle.medium(14))
                        .foregroundStyle(tab == item ? Color("OiGreen") : Color(white: 0.44))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .overlay(alignment: .bottom) {
                            if tab == item { Color("OiGreen").frame(width: 39, height: 2).padding(.bottom, 3) }
                        }
                }.buttonStyle(.plain).accessibilityIdentifier("oi.card.tab.\(item.rawValue)")
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
    }
    @ViewBuilder private var controls: some View {
        switch tab {
        case .content: contentEditor
        case .background: backgroundEditor
        case .pattern: patterns
        case .size: EmptyView() // The non-scrolling, height-constrained editor above owns this tab.
        }
    }
    private func placementEditor(height: CGFloat) -> some View {
        OiCardPlacementEditor(image: portrait, placement: designBinding(\.characterPlacement),
            frameHeight: height, compact: true,
            look: customization.wardrobe, orientation: customization.wardrobe == nil ? nil : $orientation,
            portraitKey: portraitKey ?? "", onCapture: acceptPortrait, onInteractionEnded: saveOrientation)
    }
    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Button { customization.showsCharacter = false; showingBack = false; showingPhotoEditor = true } label: {
                    Label("사진 넣기", systemImage: "photo.badge.plus").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("oi.postcard.source.photo")
                Button { customization.showsCharacter = true; showingBack = false; tab = .size } label: {
                    Label("내 오이 배치", systemImage: "leaf").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("oi.postcard.source.cucumber")
            }.tint(Color("OiGreen"))
            VStack(alignment: .leading, spacing: 16) {
                fieldHeading("오이 이름", hint: "‘오이’를 제외한 다섯 글자 이내로 작성해 주세요")
                HStack(spacing: 4) {
                    ZStack(alignment: .leading) {
                        HStack(spacing: 5) {
                            ForEach(0..<5) { index in
                                let chars = Array(nameInput)
                                Text(index < chars.count ? String(chars[index]) : "-")
                                    .font(CampusStyle.body(16)).frame(width: 31, height: 36)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                            }
                        }.opacity(editingName ? 0 : 1)
                        TextField("이름", text: $nameInput).focused($editingName)
                            .opacity(editingName ? 1 : 0.02).font(CampusStyle.body(16))
                            .submitLabel(.done).onSubmit { editingName = false }
                            .accessibilityIdentifier("oi.draft.cucumberName")
                    }.frame(width: 175)
                    Text("오이").font(CampusStyle.body(16))
                    Spacer(minLength: 5)
                    Button(editingName ? "완료" : "수정") { editingName.toggle() }
                        .font(CampusStyle.body(10)).underline().tint(Color("OiGreen"))
                }.padding(.horizontal, 20).padding(.vertical, 16)
                    .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 30))
                if nameInput.count > 5 { Text("다섯 글자까지 입력할 수 있어요.").font(.caption).foregroundStyle(.red) }
            }
            VStack(alignment: .leading, spacing: 16) {
                fieldHeading("엽서 내용", hint: "뒷면에 들어갈 이야기입니다")
                VStack(alignment: .leading, spacing: 6) {
                    TextField("엽서에 남길 이야기",
                              text: Binding(get: { draft.body }, set: { text in
                        draft.body = String(text.prefix(OiCreationStep.storyTextLimit))
                    }), axis: .vertical).lineLimit(3...5).font(CampusStyle.body(14)).lineSpacing(7)
                        .accessibilityIdentifier("oi.card.caption")
                    HStack {
                        Text("\(draft.body.count) / \(OiCreationStep.storyTextLimit)자").foregroundStyle(.secondary)
                        Spacer(); Image(systemName: "pencil").foregroundStyle(Color("OiGreen"))
                    }.font(CampusStyle.body(10))
                }.padding(20).background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 30))
            }
            HStack(spacing: 20) {
                Text("보낸 사람").font(CampusStyle.medium(16))
                Text(donorName.isEmpty ? "계정에 등록된 이름" : donorName).font(CampusStyle.body(16))
            }
            Text("뒷면에는 공개 검토를 받은 이야기와 작성자 이름이 표시돼요.").font(.caption).foregroundStyle(.secondary)
            if donorName.isEmpty {
                Text("계정에 등록된 이름을 확인하면 카드에 표시돼요.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func fieldHeading(_ title: String, hint: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(title).font(CampusStyle.medium(16))
            Text(hint).font(CampusStyle.body(9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var backgroundStyle: OiPostcardBackgroundStyle {
        design.postcardBackground ?? OiPostcardBackgroundStyle(color: design.borderFirst, fill: design.borderFill)
    }
    private func prepareBackground() {
        guard design.postcardBackground == nil else { return }
        let value = customization.card == nil ? OiPostcardBackgroundStyle() : backgroundStyle
        change { $0.postcardBackground = value }
    }
    private func updateBackground(_ edit: (inout OiPostcardBackgroundStyle) -> Void) {
        var value = backgroundStyle; edit(&value)
        change { $0.postcardBackground = value }
    }
    var backgroundEditor: some View {
        let style = backgroundStyle
        return VStack(alignment: .leading, spacing: 20) {
            Picker("배경 효과", selection: Binding(get: { style.fill }, set: { fill in
                updateBackground { $0.fill = fill }
            })) {
                Text("단색").tag(OiDraftCustomization.Fill.solid)
                Text("그라데이션").tag(OiDraftCustomization.Fill.gradient)
            }.pickerStyle(.segmented).accessibilityIdentifier("oi.postcard.background.effect")
            Text("배경색 하나로 엽서 앞·뒷면을 함께 꾸며요. 그라데이션은 은은한 밝고 어두운 톤을 자동으로 더해요.")
                .font(CampusStyle.body(12)).foregroundStyle(.secondary)
            if customization.showsCharacter {
                Text("오이 뒤에는 선택한 배경에 어울리는 짙은 색이 자동으로 들어가요.")
                    .font(CampusStyle.body(12)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 12) {
                ForEach(OiCardPalette.backgrounds) { item in
                    Button { updateBackground { $0.color = item.first } } label: {
                        VStack(spacing: 5) {
                            OiPostcardBackground(style: .init(color: item.first, fill: style.fill))
                                .frame(width: 40, height: 40).clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.8))
                                .overlay {
                                    if style.color == item.first { Circle().strokeBorder(Color("OiGreen"), lineWidth: 2) }
                                }
                            Text(item.name).font(CampusStyle.body(10)).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity, minHeight: 57)
                    }.buttonStyle(.plain).accessibilityLabel(item.name)
                        .accessibilityAddTraits(style.color == item.first ? .isSelected : [])
                }
            }.padding(.horizontal, 8)
            HStack(spacing: 8) {
                ColorPicker("배경색", selection: Binding(get: { Color(oiRGB: style.color) }, set: { color in
                    updateBackground { $0.color = color.oiRGB }
                }), supportsOpacity: false).labelsHidden().frame(width: 40, height: 40)
                    .accessibilityLabel("직접 배경색 선택")
                VStack(alignment: .leading, spacing: 2) {
                    Text("직접 배경색 선택").font(CampusStyle.medium(12))
                    Text(String(format: "#%06X", style.color)).font(CampusStyle.body(10)).foregroundStyle(.secondary)
                }
            }
            Button { customization.showsCharacter = false; showingPhotoEditor = true } label: {
                Label("사진 넣기 · 배치 수정", systemImage: "photo.badge.plus")
            }.buttonStyle(.bordered).accessibilityIdentifier("oi.postcard.photo.edit")
            Toggle("사진을 배경 색조에 맞추기", isOn: Binding(get: { design.photoMonochrome ?? false }, set: { value in
                change { $0.photoMonochrome = value }
            })).font(CampusStyle.body(13)).tint(Color("OiGreen"))
            if design.backgroundPhoto != nil {
                Button("사진 삭제", role: .destructive) { change { $0.backgroundPhoto = nil } }.font(.caption)
            }
        }.tint(Color("OiGreen"))
    }
    private var patterns: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 15), count: 4), spacing: 15) {
                ForEach(1...8, id: \.self) { number in
                    Button { change { $0.pattern = $0.pattern == number ? nil : number } } label: {
                        GeometryReader { geometry in
                            OiCardBackground(customization: customization, pattern: number)
                                .frame(width: max(1, geometry.size.width - 6), height: 103).clipped()
                                .padding(3).background(Color("OiBorder")).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(design.pattern == number ? Color("OiGreen") : .clear, lineWidth: 3))
                        }.frame(height: 109)
                    }.buttonStyle(.plain).accessibilityLabel("패턴 \(number)")
                        .accessibilityAddTraits(design.pattern == number ? .isSelected : [])
                }
            }
            if design.pattern != nil { Button("패턴 해제") { change { $0.pattern = nil } }.font(.caption).tint(Color("OiGreen")) }
        }
    }
    private var storageDetails: some View {
        DisclosureGroup("저장·공개 안내") {
            Text("꾸민 카드는 이 기기에 저장돼요. 공개 검토를 요청하면 카드 이미지도 검토하고, 승인된 모습을 다른 사람에게 보여줘요.")
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
        }.font(.caption).tint(Color("OiGreen"))
    }
    private var baseName: String { draft.cucumberName.hasSuffix("오이") ? String(draft.cucumberName.dropLast(2)) : draft.cucumberName }
    private func commitName() {
        // Visiting an older draft must not silently truncate a previously valid name.
        guard nameInput != baseName else { return }
        nameInput = String(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(5))
        draft.cucumberName = nameInput.isEmpty ? "" : nameInput + "오이"
    }
    private func refreshPortrait() {
        portraitFailed = false
        // Hash photo bytes only when the wardrobe changes, not on every drag frame.
        if let look = customization.wardrobe { wardrobeKey = OiCardPortrait.key(for: look) }
        else { wardrobeKey = nil }
        orientation = (design.characterOrientation ?? OiCardOrientation()).normalized
        restorePortrait()
    }
    private func restorePortrait() {
        if design.portraitKey == portraitKey, let data = design.portraitPNG { portrait = UIImage(data: data) }
        else { portrait = customization.wardrobe == nil ? UIImage(named: draft.cucumberAsset) : nil }
    }
    private func saveOrientation() {
        guard customization.wardrobe != nil,
              design.characterOrientation != orientation.normalized else { return }
        change { $0.characterOrientation = orientation.normalized }
    }
    private func acceptPortrait(_ data: Data, _ key: String) {
        guard key == portraitKey else { return }
        portraitFailed = false
        // Persist once after a rotation, not for every finger movement (PNG drafts can be large).
        change {
            $0.characterOrientation = orientation.normalized
            $0.portraitPNG = data; $0.portraitKey = key
        }
        portrait = UIImage(data: data)
    }
    private func change(_ edit: (inout OiCardDesign) -> Void) {
        var value = design; edit(&value); customization.card = value
    }
    private var cardBinding: Binding<OiCardDesign> {
        Binding(get: { design }, set: { customization.card = $0 })
    }
    private func designBinding<Value>(_ key: WritableKeyPath<OiCardDesign, Value>) -> Binding<Value> {
        Binding(get: { design[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
    }
}

private struct OiCardBackgroundPhotoEditor: View {
    @Binding var design: OiCardDesign
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [PHPickerResult] = []
    @State private var showingLibrary = false
    @State private var importID = UUID()
    @State private var error: String?
    @State private var importing = false
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("이미지 디자인").font(CampusStyle.semibold(20)).foregroundStyle(Color("OiDark"))
                Spacer()
                Button("완료") { dismiss() }.font(CampusStyle.medium(16)).underline().tint(.secondary)
            }
            OiCardPlacementEditor(image: design.backgroundPhoto.flatMap(UIImage.init(data:)),
                                  placement: $design.backgroundPlacement, title: "드래그·핀치로 배치하세요.",
                                  frameHeight: 190, emptyMessage: "아래에서 사진을 추가하세요")
                .frame(height: 255).clipShape(RoundedRectangle(cornerRadius: 30))
            Button { showingLibrary = true } label: {
                Label(importing ? "사진 불러오는 중" : "사진 추가", systemImage: "photo.badge.plus")
                    .font(CampusStyle.body(16)).frame(maxWidth: .infinity).frame(height: 38)
                    .background(.white, in: Capsule())
            }.disabled(importing).tint(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(20).frame(maxHeight: .infinity, alignment: .top)
            .background {
                OiWardrobePhotoLibrary(isPresented: $showingLibrary, limit: 1) { results in
                    selection = results; importID = UUID()
                }.frame(width: 0, height: 0)
            }
            .task(id: importID) {
                guard let picked = selection.first else { return }
                importing = true; defer { importing = false }
                do {
                    let bytes: Data = try await withCheckedThrowingContinuation { continuation in
                        picked.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                            if let data { continuation.resume(returning: data) }
                            else { continuation.resume(throwing: error ?? OiPhotoDataError.unreadable) }
                        }
                    }
                    let photo = try OiPhotoProcessor.prepare(bytes)
                    try Task.checkCancellation()
                    design.backgroundPhoto = photo; design.backgroundPlacement = OiCardPlacement(); error = nil
                } catch is CancellationError { }
                catch { self.error = "사진을 불러오지 못했어요. 다시 선택해 주세요." }
            }
    }
}

struct OiCreationCharacterImage: View {
    let asset: String
    var body: some View {
        if UIImage(named: asset) != nil {
            Image(asset == "OiCats" ? "OiCatsPortrait" : asset).resizable().scaledToFit().accessibilityLabel("선택한 오이")
        } else {
            ContentUnavailableView("오이 미리보기를 불러올 수 없어요", systemImage: "leaf")
        }
    }
}

extension Color {
    init(oiRGB: UInt32) {
        self.init(red: Double((oiRGB >> 16) & 255) / 255, green: Double((oiRGB >> 8) & 255) / 255, blue: Double(oiRGB & 255) / 255)
    }
    var oiRGB: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((max(0, min(1, r)) * 255).rounded()) << 16 | UInt32((max(0, min(1, g)) * 255).rounded()) << 8 | UInt32((max(0, min(1, b)) * 255).rounded())
    }
}
