import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum OiCardTab: String, CaseIterable {
    case content = "내용", background = "배경", border = "테두리", pattern = "패턴", size = "오이크기"
}

struct OiCardCustomizationStep: View {
    @Binding var draft: OiStoryDraft
    @Binding var customization: OiDraftCustomization
    let assets: [OiAsset]
    var donorName = ""
    var canContinue = true
    var isFinished = false
    var onContinue: (() -> Void)?
    var onSizeEditingChanged: ((Bool) -> Void)? = nil
    @State private var tab: OiCardTab = .content
    @State private var portrait: UIImage?
    @State private var wardrobeKey: String?
    @State private var orientation = OiCardOrientation()
    private var portraitKey: String? {
        wardrobeKey.map { $0 + "-angle-" + orientation.cacheIdentity }
    }
    @State private var showingPhotoEditor = false
    @State private var nameInput = ""
    @FocusState private var editingName: Bool
    private var design: OiCardDesign { customization.card ?? OiCardDesign() }
    private var needsPortrait: Bool { portraitKey != nil && (design.portraitKey != portraitKey || design.portraitPNG == nil) }

    private var isSizeEditing: Bool { tab == .size && !isFinished }

    var body: some View {
        GeometryReader { geometry in
            let previewHeight = isSizeEditing
                ? min(268.0, max(64.0, geometry.size.height * 0.38))
                : min(308.0, max(205.0, geometry.size.height * 0.47))
            VStack(spacing: 0) {
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
                                                    (editor.size.width - 40) * 472 / 332))
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
        .onAppear { refreshPortrait(); nameInput = baseName; onSizeEditingChanged?(isSizeEditing) }
        .onChange(of: customization.wardrobe) { _, _ in refreshPortrait() }
        .onChange(of: tab) { _, _ in saveOrientation() }
        .onChange(of: isSizeEditing) { _, editing in onSizeEditingChanged?(editing) }
        .onDisappear { saveOrientation(); onSizeEditingChanged?(false) }
        .onChange(of: editingName) { _, focused in if !focused { commitName() } }
        .onChange(of: isFinished) { _, finished in if finished { editingName = false; commitName() } }
    }

    private func preview(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            OiDraftCardPreview(draft: draft, customization: customization, donorName: donorName, portrait: portrait)
                .frame(width: height * 362 / 502, height: height)
                .overlay {
                    if needsPortrait, (tab != .size || isFinished), let look = customization.wardrobe {
                        OiCardPortraitCapture(look: look, cacheKey: portraitKey ?? "", orientation: orientation,
                                              onCapture: acceptPortrait)
                            .aspectRatio(332 / 472, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            HStack(alignment: .bottom) {
                VStack(spacing: 3) {
                    Text("오이").font(CampusStyle.medium(16))
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
                    Text(item.rawValue).font(tab == item ? CampusStyle.semibold(16) : CampusStyle.medium(16))
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
        case .background, .border: paletteEditor(border: tab == .border)
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
        VStack(alignment: .leading, spacing: 30) {
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
                fieldHeading("내용", hint: "미수정 시 이야기 작성 때 남긴 제목이 적용됩니다")
                VStack(alignment: .leading, spacing: 6) {
                    TextField(draft.title.isEmpty ? "카드에 남길 내용" : draft.title,
                              text: Binding(get: { design.caption ?? "" }, set: { text in
                        change { $0.caption = limitedCaption(text) }
                    }), axis: .vertical).lineLimit(3...5).font(CampusStyle.body(14)).lineSpacing(7)
                        .accessibilityIdentifier("oi.card.caption")
                    HStack {
                        Text("\((design.caption ?? "").utf8.count) / 1500 byte").foregroundStyle(.secondary)
                        Spacer(); Image(systemName: "pencil").foregroundStyle(Color("OiGreen"))
                    }.font(CampusStyle.body(10))
                }.padding(20).background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 30))
            }
            HStack(spacing: 20) {
                Text("기부자").font(CampusStyle.medium(16))
                ForEach([true, false], id: \.self) { anonymous in
                    Button { change { $0.anonymous = anonymous } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: design.anonymous == anonymous ? "checkmark.square.fill" : "square")
                            Text(anonymous ? "익명" : "실명")
                        }.font(CampusStyle.body(16))
                    }.buttonStyle(.plain).tint(Color("OiGreen"))
                }
            }
            Text("이름 표시는 카드 미리보기에만 적용돼요.").font(.caption).foregroundStyle(.secondary)
            if !design.anonymous && donorName.isEmpty {
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
    private func paletteEditor(border: Bool) -> some View {
        let fill = border ? design.borderFill : customization.fill
        let first = border ? design.borderFirst : customization.firstColor
        let second = border ? design.borderSecond : customization.secondColor
        let colors = OiCardPalette.items(gradient: fill == .gradient, border: border)
        return VStack(alignment: .leading, spacing: 20) {
            Picker(border ? "테두리 채우기" : "배경 채우기", selection: Binding(get: { fill }, set: { value in
                if border { change { $0.borderFill = value } } else { customization.fill = value }
            })) {
                Text("단색").tag(OiDraftCustomization.Fill.solid)
                Text("그라데이션").tag(OiDraftCustomization.Fill.gradient)
            }.pickerStyle(.segmented)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 12) {
                ForEach(colors) { item in
                    Button {
                        if border { change { $0.borderFirst = item.first; $0.borderSecond = item.second } }
                        else { customization.firstColor = item.first; customization.secondColor = item.second }
                    } label: {
                        VStack(spacing: 5) {
                            OiCardGradient(fill: fill, first: item.first, second: item.second)
                                .frame(width: 40, height: 40).clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.8))
                                .overlay {
                                    if first == item.first && (fill == .solid || second == item.second) {
                                        Circle().strokeBorder(Color("OiGreen"), lineWidth: 2)
                                    }
                                }
                            Text(item.name).font(CampusStyle.body(10)).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity, minHeight: 57)
                    }.buttonStyle(.plain).accessibilityLabel(item.name)
                }
            }.padding(.horizontal, 8)
            if fill == .gradient { Text("직접 색상 선택").font(CampusStyle.semibold(14)) }
            HStack(spacing: 16) {
                colorControl(fill == .gradient ? "시작 Color" : "직접 색상 선택", border: border, second: false)
                if fill == .gradient {
                    colorControl("끝 Color", border: border, second: true)
                } else if !border {
                    Button { showingPhotoEditor = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 16))
                                .frame(width: 40, height: 40).background(Color(white: 0.94), in: Circle())
                            Text("직접 이미지 추가").font(CampusStyle.semibold(12))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("oi.card.background.photo")
                }
            }
            if !border && design.backgroundPhoto != nil {
                HStack {
                    Button("배경 사진 배치 수정") { showingPhotoEditor = true }
                    Spacer()
                    Button("사진 삭제", role: .destructive) { change { $0.backgroundPhoto = nil } }
                }.font(.caption)
            }
        }
    }
    private func colorControl(_ title: String, border: Bool, second: Bool) -> some View {
        let value = border ? (second ? design.borderSecond : design.borderFirst) : (second ? customization.secondColor : customization.firstColor)
        return HStack(spacing: 8) {
            ColorPicker(title, selection: Binding(get: { Color(oiRGB: value) }, set: { color in
                if border { change { if second { $0.borderSecond = color.oiRGB } else { $0.borderFirst = color.oiRGB } } }
                else if second { customization.secondColor = color.oiRGB }
                else { customization.firstColor = color.oiRGB }
            }), supportsOpacity: false).labelsHidden().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(CampusStyle.medium(12))
                Text(String(format: "#%06X", value)).font(CampusStyle.body(10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
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
            Text("공개 카드에는 꾸민 오이와 아래 카드 테두리를 사용해요. 배경, 문구, 익명 표시 등 내 카드 설정은 이 기기에 저장돼요.")
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            OiCreationAssetPicker(assets: assets.filter { $0.kind == "card" }, selection: $draft.cardAsset, draft: draft)
        }.font(.caption).tint(Color("OiGreen"))
    }
    private var baseName: String { draft.cucumberName.hasSuffix("오이") ? String(draft.cucumberName.dropLast(2)) : draft.cucumberName }
    private func commitName() {
        // Visiting an older draft must not silently truncate a previously valid name.
        guard nameInput != baseName else { return }
        nameInput = String(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(5))
        draft.cucumberName = nameInput.isEmpty ? "" : nameInput + "오이"
    }
    private func limitedCaption(_ text: String) -> String {
        var result = "", bytes = 0
        for character in text {
            let count = String(character).utf8.count
            guard bytes + count <= 1500 else { break }
            result.append(character); bytes += count
        }
        return result
    }
    private func refreshPortrait() {
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

private struct OiCreationAssetPicker: View {
    let assets: [OiAsset]
    @Binding var selection: String
    var draft: OiStoryDraft?
    var body: some View {
        if assets.isEmpty {
            Text("선택할 수 있는 카드 세트가 없어요.").font(.footnote).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 10) {
                ForEach(assets) { asset in
                    Button { selection = asset.id } label: {
                        VStack(spacing: 6) {
                            if asset.kind == "cucumber" { OiCreationCharacterImage(asset: asset.id).frame(height: 76) }
                            else if let draft {
                                MYCardArtwork(card: MYCard(id: draft.id.uuidString, title: draft.cucumberName,
                                    image: draft.cucumberAsset, school: .postech, order: 0, body: draft.body,
                                    donor: "", date: "", appearance: asset.id)).frame(height: 100)
                            }
                            Text(asset.name).font(.caption).lineLimit(2)
                            if selection == asset.id { Image(systemName: "checkmark.circle.fill") }
                        }.frame(maxWidth: .infinity).padding(10)
                            .background(selection == asset.id ? Color("OiBorder") : Color("OiLight"), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).tint(Color("OiGreen"))
                        .accessibilityAddTraits(selection == asset.id ? .isSelected : [])
                }
            }
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
