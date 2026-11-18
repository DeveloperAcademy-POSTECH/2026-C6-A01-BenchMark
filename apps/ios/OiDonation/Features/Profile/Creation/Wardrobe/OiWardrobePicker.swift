import SwiftUI

private enum OiWardrobeTab: String, CaseIterable {
    // Figma `5719:9790`: 내용 comes first (#377).
    case content = "내용", pose = "포즈", top = "상의", bottom = "하의", shoes = "신발", hat = "모자", set = "세트", accessory = "악세서리", special = "스페셜"
    var isAvailable: Bool { [.content, .top, .bottom, .shoes, .set].contains(self) }
    var isClothing: Bool { [.top, .bottom, .shoes, .set].contains(self) }

    var seedColorSlot: OiSeedCucumberGarment.Slot? {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .shoes: .shoes
        default: nil
        }
    }
}

struct OiCucumberCustomizationStep: View {
    enum PreviewMode {
        case seed
        case wardrobe
    }

    @Binding var customization: OiDraftCustomization
    /// The draft's cucumber name, edited in the 내용 tab. Nil hides the tab's name field.
    var cucumberName: Binding<String>?
    var previewMode: PreviewMode = .seed
    var canContinue = true
    var isFinished = false
    var onContinue: (() -> Void)?
    var onPhotoEditingChanged: (Bool) -> Void = { _ in }
    /// Opens on a tab by its title (e.g. "상의"); used by visual checks.
    var initialTabTitle: String?
    @Environment(\.oiCustomizationBottomInset) private var bottomInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var photoScene: OiWardrobeScene?
    @State private var tab: OiWardrobeTab = .content
    @State private var wardrobeScrollPosition = ScrollPosition()
    @State private var photoSlot: OiPhotoSlot?
    /// Top of the keyboard in global coordinates, animated with the keyboard itself (#377).
    @State private var keyboardTop: CGFloat?
    @State private var showsFaceEditor = false
    private var allowsWardrobeEditing: Bool { previewMode == .wardrobe }
    private var seedAppearance: OiSeedCucumberAppearance { customization.seedAppearance ?? .init() }
    private var look: OiWardrobeLook { customization.wardrobe ?? OiWardrobeLook() }
    private var photoLook: OiWardrobeLook { allowsWardrobeEditing ? look : customization.seedPhotoLook }
    private var hasSeedPhotoTop: Bool { customization.seedGarments.contains { $0.photoTop != nil } }
    private var photoSeed: OiSeedCucumberSnapshot? { allowsWardrobeEditing ? nil : customization.seedSnapshot }
    private var seedGarmentColors: [OiSeedCucumberGarment.Slot: UInt32] {
        guard customization.selectedSeedSet == nil else { return [:] }
        var result: [OiSeedCucumberGarment.Slot: UInt32] = [:]
        for tab in [OiWardrobeTab.top, .bottom, .shoes] {
            if let slot = tab.seedColorSlot, let color = savedSeedColor(for: tab) {
                result[slot] = color
            }
        }
        return result
    }
    /// Tabs, the name label and its field must stay above the keyboard while typing.
    private static let nameEditingClearance: CGFloat = 44 + 15 + 32 + 70 + 16

    /// Shrinks the cucumber only as far as the keyboard requires.
    private func previewHeight(full: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        guard let keyboardTop, photoSlot == nil else { return full }
        let frame = geometry.frame(in: .global)
        let overlap = max(0, frame.maxY - keyboardTop)
        let available = frame.height - overlap - Self.nameEditingClearance - 22
        return min(full, max(120, available))
    }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = min(462.0, max(300.0, geometry.size.height - 180))
            let scrollsItemTray = !allowsWardrobeEditing && verticalSizeClass == .compact
            VStack(spacing: 0) {
                // Each active preview owns one RealityKit surface, including photo editing.
                // Figma `5719:9790`: the cucumber area ends about 14pt above the tabs at y=491.
                let fullHeight = photoSlot != nil ? max(160, geometry.size.height - panelHeight)
                    : min(320, geometry.size.height * 0.5)
                preview(height: previewHeight(full: fullHeight, in: geometry), fullHeight: fullHeight)
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 14)
                    // While the image sheet is open, a tap above it closes the sheet without saving (#377).
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { if photoSlot != nil { closePhotoEditor() } })
                if let slot = photoSlot, let photoScene {
                    OiWardrobePhotoEditor(slot: slot, look: photoLook, scene: photoScene,
                        onClose: closePhotoEditor, seed: photoSeed,
                        photoResource: allowsWardrobeEditing ? nil : OiSeedGarmentPhotoMaterial.resource(for: photoLook.top)) { artwork in
                            change { $0.artwork = artwork }
                        }
                        .frame(height: panelHeight)
                        // Figma `5719:9585`: #EAEEE2 sheet, 35pt top corners, soft shadow.
                        .background {
                            UnevenRoundedRectangle(topLeadingRadius: 35, topTrailingRadius: 35)
                                .fill(Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255))
                                .shadow(color: .black.opacity(0.25), radius: 5)
                                .ignoresSafeArea(.container, edges: .bottom)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        if !isFinished {
                            wardrobeTabs.frame(height: 44).padding(.horizontal, 20)
                            // Keep the tray fixed in portrait, but leave room to reach the colors in landscape.
                            if showsItemTray && !scrollsItemTray {
                                itemStrip.padding(.horizontal, 20).padding(.bottom, 4)
                            }
                        }
                        ScrollView {
                            VStack(spacing: 16) {
                                if isFinished {
                                    Text("오이 꾸미기를 마쳤어요").font(CampusStyle.semibold(20))
                                    Text("다음을 눌러 카드와 오이 이름을 설정해 주세요.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                } else {
                                    if scrollsItemTray && showsItemTray { itemStrip }
                                    wardrobeControls
                                }
                            // Figma: the 내용 tab starts 15pt below the tabs, the item tray directly under them.
                            }.padding(.horizontal, 20).padding(.top, tab == .content || isFinished ? 15 : 0)
                                .padding(.bottom, 24 + bottomInset)
                        }
                        // The 내용 tab fits on screen, so it does not scroll (#377).
                        .scrollDisabled(tab == .content && !isFinished)
                        .modifier(OiCustomizationScrollEdge())
                        .accessibilityIdentifier("oi.wardrobe.settingsScroll")
                        .scrollPosition($wardrobeScrollPosition)
                        .onChange(of: tab) { _, _ in wardrobeScrollPosition.scrollTo(edge: .top) }
                    }
                }
            }
            // Figma `5719:9790`: one white page without the separate grey preview and panel (#377).
            .background(Color.white.ignoresSafeArea(.container, edges: .bottom))
        }
        // Follow the keyboard ourselves so the cucumber scales with the keyboard animation
        // instead of the 3D view jumping to a new size (#377).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboardChanged(note, hiding: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            keyboardChanged(note, hiding: true)
        }
        .onAppear {
            if allowsWardrobeEditing {
                if photoScene == nil { photoScene = OiWardrobeScene() }
                if customization.wardrobe == nil { customization.wardrobe = OiWardrobeLook() }
            }
            if let title = initialTabTitle, let initial = OiWardrobeTab(rawValue: title) { tab = initial }
        }
        .sheet(isPresented: $showsFaceEditor) {
            NavigationStack {
                OiSeedCucumberCustomizationView(appearance: seedAppearance) { appearance in
                    customization.seedAppearance = appearance
                }
            }
        }
    }

    private func keyboardChanged(_ note: Notification, hiding: Bool) {
        let info = note.userInfo ?? [:]
        let end = (info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let top: CGFloat? = hiding || end.height == 0 ? nil : end.minY
        guard top != keyboardTop else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: max(0.25, duration))) { keyboardTop = top }
    }

    private func preview(height: CGFloat, fullHeight: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if (allowsWardrobeEditing || photoSlot != nil), let photoScene {
                OiWardrobePreview(look: photoLook, controls: false, scene: photoScene,
                                  backgroundColor: .white, portraitKey: customization.card?.portraitKey,
                                  portraitPNG: customization.card?.portraitPNG, seed: photoSeed)
                    .frame(height: fullHeight)
                    .scaleEffect(fullHeight > 0 ? min(1, height / fullHeight) : 1)
                    .frame(height: height)
                    .overlay(alignment: .topTrailing) {
                        if photoSlot != nil {
                            Text("실시간 미리보기").font(.caption2).foregroundStyle(Color("OiGreen")).padding(8)
                        }
                    }
            } else if allowsWardrobeEditing {
                Color.clear.frame(height: height)
            } else {
                OiStep3CucumberPreview(appearance: seedAppearance, garments: customization.seedGarments,
                                       garmentColors: seedGarmentColors,
                                      photoLook: customization.seedPhotoLook,
                                      isActive: !showsFaceEditor)
                    .frame(height: fullHeight)
                    .scaleEffect(fullHeight > 0 ? min(1, height / fullHeight) : 1)
                    .frame(height: height)
            }
            if photoSlot == nil {
                Group {
                    if allowsWardrobeEditing, let photoScene {
                        OiWardrobeRotationHint()
                            .accessibilityAction(named: "오른쪽으로 돌리기") { photoScene.orbit(-157) }
                            .accessibilityAction(named: "왼쪽으로 돌리기") { photoScene.orbit(157) }
                    } else {
                        OiWardrobeRotationHint().accessibilityHidden(true)
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                VStack(alignment: .trailing, spacing: 8) {
                    if !allowsWardrobeEditing && !isFinished {
                        OiCustomizationResetButton {
                            customization.resetCucumberAppearance()
                        }.accessibilityIdentifier("oi.wardrobe.reset")
                        OiCreationDoneButton(title: "얼굴") { showsFaceEditor = true }
                            .accessibilityIdentifier("oi.customization.face")
                            .accessibilityHint("오이 얼굴과 몸체를 편집해요")
                    }
                    if let onContinue {
                        OiCreationDoneButton(enabled: canContinue, title: isFinished ? "다시 꾸미기" : "완료", action: onContinue)
                            .accessibilityIdentifier("oi.customization.done")
                            .accessibilityHint(isFinished ? "꾸미기를 다시 열어요" : "카드 꾸미기로 이동해요")
                    }
                }
            }
        }
    }

    private func closePhotoEditor() {
        if allowsWardrobeEditing { photoScene?.editPhotos(in: nil, look: look) }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { photoSlot = nil }
        onPhotoEditingChanged(false)
    }

    private func openPhotoEditor(_ slot: OiPhotoSlot) {
        guard allowsWardrobeEditing || hasSeedPhotoTop else { return }
        let scene = photoScene ?? OiWardrobeScene()
        photoScene = scene
        scene.editPhotos(in: slot, look: photoLook, seed: photoSeed)
        onPhotoEditingChanged(true)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { photoSlot = slot }
    }

    /// Figma `5719:9606`: tabs spread across the width; the selected one is bold green with a 39pt underline.
    private var wardrobeTabs: some View {
        let categories = OiWardrobeTab.allCases.filter(\.isAvailable)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    if index > 0 { Spacer(minLength: 12) }
                    tabButton(category)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) { ForEach(categories, id: \.self) { tabButton($0) } }
            }
        }
    }

    private func tabButton(_ category: OiWardrobeTab) -> some View {
        let selected = tab == category
        return Button {
            if tab == .content, category != .content {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            tab = category
        } label: {
            VStack(spacing: 5) {
                Text(category.rawValue)
                    .font(selected ? .custom("Paperlogy-7Bold", size: 16, relativeTo: .body) : CampusStyle.medium(16))
                    .tracking(0.32)
                Rectangle().fill(selected ? Color("OiGreen") : .clear).frame(width: 39, height: 2)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(OiCreationPressStyle())
        .foregroundStyle(selected ? Color("OiGreen") : Color(white: 113 / 255))
        .accessibilityIdentifier("oi.wardrobe.tab.\(category.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var wardrobeControls: some View {
        if tab == .content {
            if let cucumberName { OiCucumberNameField(name: cucumberName) }
        } else {
            clothingControls
        }
    }

    @ViewBuilder private var clothingControls: some View {
        if tab == .set {
            // Same #D9D9D9 tray as 상의·하의 (#377).
            items.id(tab).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 217 / 255), in: RoundedRectangle(cornerRadius: 10))
            if let slot = selectedPhotoSlot { photoControls(slot) }
        } else {
            // Figma `5719:9981` 상의 (also 하의·신발): the fixed item tray above, then custom color/image, colors and denim.
            VStack(alignment: .leading, spacing: 20) {
                // The postech jacket keeps its colors while still accepting a photo print.
                if showsColors || selectedPhotoSlot != nil {
                    HStack(spacing: 21) {
                        if showsColors { customColorButton }
                        if let slot = selectedPhotoSlot { addImageButton(slot) }
                    }
                }
                if showsColors { colorRows }
                if allowsWardrobeEditing, let slot = selectedPhotoSlot, showsColors { denimRow(slot) }
            }
            .padding(.horizontal, 8).padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var showsItemTray: Bool { [.top, .bottom, .shoes].contains(tab) }

    /// The postech jacket and one-piece sets keep their own colors.
    private var showsColors: Bool {
        guard tab.seedColorSlot != nil else { return false }
        if allowsWardrobeEditing {
            return look.costume == nil && !(tab == .top && look.top == .postech)
        }
        return customization.selectedSeedSet == nil && !(tab == .top && customization.selectedSeedTop == .postech)
    }

    /// Figma `5719:10056`: up to four 76×112 white cards centered on a #D9D9D9 tray, without scrolling.
    private var itemStrip: some View {
        HStack(spacing: 12) {
            switch tab {
            case .top:
                ForEach(OiWardrobeLook.Top.allCases, id: \.self) { top in
                    let selected = allowsWardrobeEditing
                        ? look.costume == nil && look.top == top
                        : customization.selectedSeedSet == nil && customization.selectedSeedTop == top
                    card(top.title, image: "oi-thumb-\(top.rawValue)", selected: selected, id: top.rawValue) {
                        if allowsWardrobeEditing {
                            change { $0.top = top; $0.costume = nil }
                        } else {
                            customization.selectSeedTop(top)
                        }
                    }
                }
            case .bottom:
                ForEach(OiWardrobeLook.Bottom.allCases, id: \.self) { bottom in
                    let selected = allowsWardrobeEditing
                        ? look.costume == nil && look.bottom == bottom
                        : customization.selectedSeedSet == nil && customization.selectedSeedBottom == bottom
                    card(bottom.title, image: "oi-thumb-\(bottom == .long ? "long-pants" : "shorts")",
                         selected: selected, id: bottom.rawValue) {
                        if allowsWardrobeEditing {
                            change { $0.bottom = bottom; $0.costume = nil }
                        } else {
                            customization.selectSeedBottom(bottom)
                        }
                    }
                }
            case .shoes:
                let selected = allowsWardrobeEditing
                    ? look.costume == nil
                    : customization.selectedSeedSet == nil && customization.seedSneakers == true
                card(OiSeedCucumberGarment.sneakers.title, image: "oi-thumb-sneakers", selected: selected, id: "sneakers") {
                    if allowsWardrobeEditing {
                        change { $0.shoeColor = 0xFFFFFF; $0.costume = nil }
                    } else {
                        customization.toggleSeedSneakers()
                    }
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 131)
        .background(Color(white: 217 / 255), in: RoundedRectangle(cornerRadius: 10))
        .id(tab)
    }

    private func card(_ title: String, image: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let url = Bundle.main.url(forResource: image, withExtension: "png") ?? Bundle.main.url(forResource: image, withExtension: "jpg"), let thumbnail = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 76)
                } else {
                    Image(systemName: "tshirt").font(.system(size: 30)).frame(maxHeight: 76)
                }
                Text(title).font(CampusStyle.body(12)).tracking(0.24).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 12)
            .frame(width: 76, height: 112)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color("OiGreen") : .clear, lineWidth: 2) }
            .overlay(alignment: .topTrailing) { if selected { OiWardrobeSelectedBadge().padding(.top, 6).padding(.trailing, 6) } }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("oi.wardrobe.item.\(id)")
        .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Figma `5719:9986`: the system color well next to its label and current RGB.
    private var customColorButton: some View {
        HStack(spacing: 10) {
            ColorPicker("직접 색상 선택", selection: customColor, supportsOpacity: false)
                .labelsHidden().frame(width: 40, height: 40)
                .accessibilityLabel("\(tab.rawValue) 직접 색상 선택")
                .accessibilityIdentifier("oi.wardrobe.color.custom")
            VStack(alignment: .leading, spacing: 2) {
                Text("직접 색상 선택").font(.custom("Paperlogy-7Bold", size: 13, relativeTo: .footnote)).tracking(0.26)
                    .foregroundStyle(Color(white: 49 / 255))
                Text("RGB 0-255 #" + String(format: "%06X", currentColor)).font(CampusStyle.body(10)).tracking(0.2)
                    .foregroundStyle(Color(red: 170 / 255, green: 167 / 255, blue: 167 / 255))
            }
        }
    }

    /// Figma `5719:9991`: opens the photo editor for the selected garment.
    private func addImageButton(_ slot: OiPhotoSlot) -> some View {
        let design = photoLook.artwork.designs[slot.itemID(in: photoLook)]
        return Button {
            openPhotoEditor(slot)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.plus").font(.system(size: 14))
                    .foregroundStyle(Color(white: 123 / 255))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white))
                    .overlay(Circle().strokeBorder(Color(white: 225 / 255), lineWidth: 4))
                Text(design == nil ? "직접 이미지 추가" : "직접 이미지 수정")
                    .font(.custom("Paperlogy-7Bold", size: 13, relativeTo: .footnote)).tracking(0.26)
                    .foregroundStyle(Color(white: 49 / 255))
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("oi.wardrobe.photo.edit")
        .disabled(!allowsWardrobeEditing && !hasSeedPhotoTop)
        .accessibilityHint(!allowsWardrobeEditing && !hasSeedPhotoTop ? "상의를 먼저 선택해 주세요" : "상의 앞면과 뒷면에 사진을 배치해요")
    }

    /// Figma `5719:9997`: two rows of six 40pt swatches, 21pt apart.
    private var colorRows: some View {
        VStack(alignment: .leading, spacing: 16) {
            colorRow(Self.neutral)
            colorRow(Self.pastel)
        }
    }

    private func colorRow(_ row: [Swatch]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 21) {
                ForEach(row) { swatch($0) }
            }
            HStack(spacing: 0) {
                ForEach(row) { swatch($0).frame(maxWidth: .infinity) }
            }
        }
    }

    private func swatch(_ color: Swatch) -> some View {
        let (name, rgb) = (color.name, color.rgb)
        let selected = allowsWardrobeEditing
            ? currentFabric == nil && currentColor == rgb
            : savedSeedColor(for: tab) == rgb
        return Button { selectColor(rgb) } label: {
            VStack(spacing: 5) {
                Circle().fill(Color(UIColor(wardrobeRGB: rgb)))
                    .overlay {
                        Circle().strokeBorder(selected ? Color("OiGreen") : Color(UIColor(wardrobeRGB: color.border)),
                                              lineWidth: selected ? 2 : 1)
                    }
                    .frame(width: 40, height: 40)
                Text(name).font(CampusStyle.body(10)).tracking(0.2).foregroundStyle(Color(white: 49 / 255))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.frame(width: 40)
        }
        .buttonStyle(.plain).accessibilityLabel("\(tab.rawValue) \(name)")
        .accessibilityIdentifier("oi.wardrobe.color.\(name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Figma `5719:10036` 질감: the six denim textures.
    private func denimRow(_ slot: OiPhotoSlot) -> some View {
        HStack(spacing: 21) {
            ForEach(OiDenim.allCases) { fabric in
                let selected = currentFabric == fabric
                Button { change { $0.fabrics[slot.itemID(in: look)] = fabric } } label: {
                    VStack(spacing: 5) {
                        Group {
                            if let image = OiPhotoRenderer.fabricImage(fabric) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else { Color.gray }
                        }
                        .frame(width: 40, height: 40).clipShape(Circle())
                        .overlay { Circle().strokeBorder(selected ? Color("OiGreen") : Color.black.opacity(0.08), lineWidth: selected ? 2 : 1) }
                        Text(fabric.title).font(CampusStyle.body(10)).tracking(0.2).foregroundStyle(Color(white: 49 / 255))
                    }.frame(width: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.rawValue) \(fabric.title) 데님")
                .accessibilityIdentifier("oi.wardrobe.denim.\(fabric.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var selectedPhotoSlot: OiPhotoSlot? {
        if !allowsWardrobeEditing {
            if tab == .top { return .top }
            return tab == .set && customization.selectedSeedSet == .postech ? .top : nil
        }
        let slot: OiPhotoSlot? = tab == .top ? .top : tab == .bottom ? .bottom : tab == .set && look.costume != nil ? .top : nil
        return slot?.supports(look) == true ? slot : nil
    }
    private func photoControls(_ slot: OiPhotoSlot) -> some View {
        let design = photoLook.artwork.designs[slot.itemID(in: photoLook)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    openPhotoEditor(slot)
                } label: {
                    Label(design == nil ? "사진으로 옷 꾸미기" : "사진 디자인 수정 · \(design?.layers.count ?? 0)장", systemImage: "photo.badge.plus")
                        .font(CampusStyle.semibold(15)).frame(maxWidth: .infinity, minHeight: 36)
                }.buttonStyle(.borderedProminent).tint(Color("OiGreen")).accessibilityIdentifier("oi.wardrobe.photo.edit")
                if design != nil {
                    Button("지우기", role: .destructive) {
                        change { try? $0.artwork.set(nil, for: slot.itemID(in: photoLook)) }
                    }.font(.caption).accessibilityIdentifier("oi.wardrobe.photo.remove")
                }
            }
            Text(slot.preservesOriginalMaterial(in: look)
                ? "얼굴·손·소품을 제외한 옷의 앞뒤 몸판에 각각 최대 2장을 넣어요. 원래 무늬는 유지돼요."
                : "앞·뒷면에 각각 최대 2장을 놓고, 드래그와 핀치로 조절해 보세요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var items: some View {
        if !tab.isAvailable {
            Text("\(tab.rawValue) 아이템은 준비 중이에요.")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 88)
        } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            switch tab {
            case .content, .pose, .hat, .accessory, .special:
                EmptyView()
            case .top, .bottom, .shoes:
                EmptyView()
            case .set:
                ForEach(allowsWardrobeEditing ? OiWardrobeLook.Costume.allCases : OiSeedCucumberSet.availableCostumes) { costume in
                    if !allowsWardrobeEditing, let proposal = OiSeedCostumeProposal.options(for: costume).first {
                        proposalItem(costume, proposal)
                    } else {
                        let seedSelection = allowsWardrobeEditing ? nil : customization.selectedSeedSet == .costume(costume)
                        item(costume.title, image: costume.thumbnailName, selected: look.costume == costume,
                             id: "set-" + costume.rawValue, seedSelection: seedSelection) {
                            if seedSelection != nil {
                                customization.selectSeedSet(.costume(costume))
                            } else {
                                change { $0.costume = costume }
                            }
                        }
                    }
                }
                let seedSelection = allowsWardrobeEditing ? nil : customization.selectedSeedSet == .postech
                item("포스텍 과잠 세트", image: "oi-look-postech",
                     selected: look.costume == nil && look.top == .postech && look.bottom == .long,
                     id: "set-postech", seedSelection: seedSelection) {
                    if seedSelection != nil {
                        customization.selectSeedSet(.postech)
                    } else {
                        var replacement = OiWardrobeLook()
                        replacement.top = .postech
                        replacement.artwork = look.artwork; replacement.fabrics = look.fabrics
                        customization.wardrobe = replacement
                    }
                }
            }
        }
        }
    }

    private func proposalItem(_ costume: OiWardrobeLook.Costume, _ proposal: OiSeedCostumeProposal) -> some View {
        let isSelected = customization.selectedSeedSet == .costume(costume)
            && customization.selectedSeedProposal == proposal
        let garment = OiSeedCucumberGarment.costumeProposal(costume, proposal)
        return item(costume.title, image: garment.rawValue, selected: isSelected,
                    id: "set-\(costume.rawValue)-proposal-\(proposal.rawValue)", seedSelection: isSelected) {
            customization.selectSeedProposal(proposal, for: costume)
        }
    }

    @ViewBuilder private func item(_ title: String, image: String, selected: Bool, id: String,
                                   seedSelection: Bool? = nil, action: @escaping () -> Void) -> some View {
        let isSelected = seedSelection ?? (allowsWardrobeEditing && selected)
        let tile = VStack(spacing: 5) {
            if let url = Bundle.main.url(forResource: image, withExtension: "png") ?? Bundle.main.url(forResource: image, withExtension: "jpg"), let thumbnail = UIImage(contentsOfFile: url.path) {
                Image(uiImage: thumbnail).resizable().scaledToFit().frame(height: 68)
            } else {
                Image(systemName: "tshirt").font(.system(size: 30)).frame(height: 68)
            }
            Text(title).font(CampusStyle.body(10)).lineLimit(2).frame(minHeight: 26)
        }.padding(5).frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color("OiGreen") : .clear, lineWidth: 2) }
            .overlay(alignment: .topTrailing) {
                if isSelected { OiWardrobeSelectedBadge().padding(.top, 6).padding(.trailing, 6) }
            }
        if allowsWardrobeEditing || seedSelection != nil {
            Button(action: action) { tile }
                .buttonStyle(.plain).foregroundStyle(Color("OiDark"))
                .accessibilityIdentifier("oi.wardrobe.item.\(id)")
                .accessibilityLabel(title).accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(seedSelection.map { $0 ? "선택하면 벗어요" : "선택하면 착용해요" } ?? "")
        } else {
            tile.foregroundStyle(Color("OiDark"))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("oi.wardrobe.item.\(id)")
                .accessibilityLabel(title)
        }
    }

    private struct Swatch: Identifiable {
        let name: String
        let rgb: UInt32
        let border: UInt32
        var id: UInt32 { rgb }

        init(_ name: String, _ rgb: UInt32, _ border: UInt32) {
            self.name = name
            self.rgb = rgb
            self.border = border
        }
    }

    // Figma `5719:9998` and `5719:10017`: use the original swatch fills and strokes.
    private static let neutral: [Swatch] = [
        .init("화이트", 0xFFFFFF, 0xDFDFDF), .init("아이보리", 0xF4EBDD, 0xDDD7CD),
        .init("오트밀", 0xD8CBB6, 0xBFB5A6), .init("토프", 0xB6A097, 0x9D938A),
        .init("스톤", 0xB7BEBA, 0xA8A9A6), .init("차콜", 0x575958, 0x515352)
    ]
    private static let pastel: [Swatch] = [
        .init("세이지", 0xC7D8C1, 0xC4CDC3), .init("민트", 0xC2DDD4, 0xB1CAC2),
        .init("스카이", 0xC5DBEC, 0xB6C7D5), .init("라벤더", 0xD6CCE6, 0xC8BFD9),
        .init("블러시", 0xEDCBD1, 0xD4BCC1), .init("버터", 0xF0E2B0, 0xD1CBA6)
    ]
    private func savedSeedColor(for tab: OiWardrobeTab) -> UInt32? {
        guard let saved = customization.garmentColors[tab.rawValue], saved <= 0xFFFFFF else { return nil }
        return saved
    }

    private var currentColor: UInt32 {
        if !allowsWardrobeEditing { return savedSeedColor(for: tab) ?? 0xFFFFFF }
        return tab == .bottom ? look.bottomColor : tab == .shoes ? look.shoeColor : look.topColor
    }
    private var currentFabric: OiDenim? { selectedPhotoSlot?.fabric(in: look) }
    private var customColor: Binding<Color> {
        Binding(get: { Color(UIColor(wardrobeRGB: currentColor)) }, set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            func channel(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
            selectColor((channel(red) << 16) | (channel(green) << 8) | channel(blue))
        })
    }
    private func selectColor(_ rgb: UInt32) {
        guard showsColors else { return }
        if !allowsWardrobeEditing {
            customization.garmentColors[tab.rawValue] = rgb
            return
        }
        change { value in
            if let slot = selectedPhotoSlot { value.fabrics.removeValue(forKey: slot.itemID(in: value)) }
            switch tab {
            case .top: value.topColor = rgb
            case .bottom: value.bottomColor = rgb
            case .shoes: value.shoeColor = rgb
            case .content, .set, .pose, .hat, .accessory, .special: break
            }
        }
    }
    private func change(_ action: (inout OiWardrobeLook) -> Void) {
        var value = look; action(&value); customization.wardrobe = value
    }
}

/// Figma `5719:10124` 오이 이름: five letter boxes before a fixed "오이", edited after tapping 수정 (#377).
struct OiCucumberNameField: View {
    @Binding var name: String
    @State private var editing = false
    @State private var input = ""
    static let letterLimit = 5

    private var baseName: String { name.hasSuffix("오이") ? String(name.dropLast(2)) : name }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("오이 이름").font(CampusStyle.medium(16)).foregroundStyle(.black)
                Text("‘오이’를 제외한 다섯글자 이내 오이이름을 작성해주세요")
                    .font(.custom("Paperlogy-3Light", size: 10, relativeTo: .caption2))
                    .foregroundStyle(Color(white: 171 / 255))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack {
                if editing {
                    OiLimitedTextField(text: $input, limit: Self.letterLimit,
                                       placeholder: "다섯 글자 이내", onEnd: commit)
                        .frame(minHeight: 36)
                    Text("오이").font(CampusStyle.body(16)).tracking(0.32)
                } else {
                    Button(action: beginEditing) { letterBoxes }
                        .buttonStyle(.plain)
                        .accessibilityHint("두 번 탭하여 오이 이름을 수정해요")
                        .accessibilityIdentifier("oi.cucumberName.boxes")
                }
                Spacer(minLength: 8)
                Button(editing ? "완료" : "수정") {
                    if editing {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        commit()
                    } else {
                        beginEditing()
                    }
                }
                    .font(CampusStyle.body(10)).tracking(0.2).underline()
                    .foregroundStyle(Color("OiGreen"))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("oi.cucumberName.edit")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(minHeight: 70)
            .background(Color(white: 247 / 255), in: RoundedRectangle(cornerRadius: 30))
            if editing && input.count > Self.letterLimit {
                Text("다섯 글자까지 입력할 수 있어요.").font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var letterBoxes: some View {
        let letters = Array(baseName)
        return HStack(spacing: 5) {
            ForEach(0..<Self.letterLimit, id: \.self) { index in
                Text(index < letters.count ? String(letters[index]) : "-")
                    .font(CampusStyle.body(16)).tracking(0.32)
                    .frame(width: 31, height: 36)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("오이").font(CampusStyle.body(16)).tracking(0.32).padding(.leading, 5)
        }
        .foregroundStyle(.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(baseName.isEmpty ? "오이 이름 없음" : "오이 이름 \(name)")
    }

    private func beginEditing() {
        input = baseName
        editing = true
    }

    private func commit() {
        let trimmed = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.letterLimit))
        // An older name that already fits is kept as is when nothing changed.
        guard editing else { return }
        if trimmed != baseName { name = trimmed.isEmpty ? "" : trimmed + "오이" }
        editing = false
    }
}

/// A UIKit field that limits letters only after Korean composition finishes; SwiftUI `TextField`
/// keeps showing composed text that its binding rejected (#377).
struct OiLimitedTextField: UIViewRepresentable {
    @Binding var text: String
    let limit: Int
    var placeholder = ""
    var onEnd: () -> Void = {}

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = UIFont(name: "Paperlogy-4Regular", size: 16) ?? .systemFont(ofSize: 16)
        field.defaultTextAttributes[.kern] = 0.32
        field.textColor = .black
        field.placeholder = placeholder
        field.returnKeyType = .done
        field.text = text
        field.delegate = context.coordinator
        field.accessibilityIdentifier = "oi.draft.cucumberName.step3"
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.markedTextRange == nil, field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OiLimitedTextField
        init(_ parent: OiLimitedTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            // Wait until a Korean syllable is committed before counting it.
            guard field.markedTextRange == nil else { return }
            var value = field.text ?? ""
            // Past the limit, keep the previous text (an older longer name may still be shortened).
            if value.count > parent.limit && value.count >= parent.text.count {
                value = parent.text.count <= parent.limit ? parent.text : String(value.prefix(parent.limit))
                field.text = value
            }
            parent.text = value
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool { field.resignFirstResponder(); return true }
        func textFieldDidEndEditing(_ field: UITextField) { changed(field); parent.onEnd() }
    }
}

/// Figma `5400:8139` 체크 표시: a 16pt #708C40 circle with a white bold check.
struct OiWardrobeSelectedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Color("OiGreen"), in: Circle())
            .accessibilityHidden(true)
    }
}
