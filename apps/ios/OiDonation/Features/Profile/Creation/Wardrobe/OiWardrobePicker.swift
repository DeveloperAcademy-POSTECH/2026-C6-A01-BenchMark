import SwiftUI

private enum OiWardrobeTab: String, CaseIterable {
    case pose = "포즈", top = "상의", bottom = "하의", shoes = "신발", hat = "모자", set = "세트", accessory = "악세서리", special = "스페셜"
    var isAvailable: Bool { [.top, .bottom, .shoes, .set].contains(self) }
}

struct OiCucumberCustomizationStep: View {
    @Binding var draft: OiStoryDraft
    @Binding var customization: OiDraftCustomization
    let assets: [OiAsset]
    var canContinue = true
    var isFinished = false
    var onContinue: (() -> Void)?
    var onPhotoEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photoScene = OiWardrobeScene()
    @State private var tab: OiWardrobeTab = .top
    @State private var photoSlot: OiPhotoSlot?
    private var look: OiWardrobeLook { customization.wardrobe ?? OiWardrobeLook() }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = min(462.0, max(300.0, geometry.size.height - 180))
            VStack(spacing: 0) {
                // Keep one RealityKit surface mounted while opening/closing the tools.
                preview(height: photoSlot != nil ? max(160, geometry.size.height - panelHeight)
                    : min(isFinished ? 350 : 270, geometry.size.height * 0.52))
                    .padding(.horizontal, 20)
                if let slot = photoSlot {
                    OiWardrobePhotoEditor(slot: slot, look: look, scene: photoScene,
                        onClose: closePhotoEditor) { artwork in
                            change { $0.artwork = artwork }
                        }
                        .frame(height: panelHeight)
                        .background {
                            UnevenRoundedRectangle(topLeadingRadius: 35, topTrailingRadius: 35)
                                .fill(CampusStyle.mapSheet)
                                .ignoresSafeArea(.container, edges: .bottom)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if isFinished {
                                Text("오이 꾸미기를 마쳤어요").font(CampusStyle.semibold(20))
                                Text("다음을 눌러 카드와 오이 이름을 설정해 주세요.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                wardrobeControls
                            }
                        }.padding(.horizontal, 20).padding(.vertical, 16)
                    }
                }
            }
        }
        .onAppear {
            if customization.wardrobe == nil { customization.wardrobe = OiWardrobeLook() }
            if look.costume != nil { tab = .set }
        }
    }

    private func preview(height: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            OiWardrobePreview(look: look, controls: photoSlot == nil, scene: photoScene)
                .frame(height: height)
                .overlay(alignment: .topTrailing) {
                    if photoSlot != nil {
                        Text("실시간 미리보기").font(.caption2).foregroundStyle(Color("OiGreen")).padding(8)
                    }
                }
            if photoSlot == nil, let onContinue {
                OiCreationDoneButton(enabled: canContinue, title: isFinished ? "다시 꾸미기" : "완료", action: onContinue)
                    .accessibilityIdentifier("oi.customization.done")
                    .accessibilityHint(isFinished ? "의상 선택을 다시 열어요" : "코디를 확인하고 이전·다음 버튼을 표시해요")
            }
        }
    }

    private func closePhotoEditor() {
        photoScene.editPhotos(in: nil, look: look)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { photoSlot = nil }
        onPhotoEditingChanged(false)
    }

    @ViewBuilder private var wardrobeControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 20) {
            ForEach(OiWardrobeTab.allCases, id: \.self) { category in
                Button { tab = category } label: {
                    Text(category.rawValue).font(tab == category ? CampusStyle.semibold(16) : CampusStyle.medium(16))
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if tab == category { Rectangle().fill(Color("OiGreen")).frame(height: 2) }
                        }
                }.buttonStyle(OiCreationPressStyle()).foregroundStyle(tab == category ? Color("OiGreen") : .secondary)
                    .accessibilityIdentifier("oi.wardrobe.tab.\(category.rawValue)")
                    .accessibilityAddTraits(tab == category ? .isSelected : [])
            }
          }
        }
        items.id(tab).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("OiSoft"), in: RoundedRectangle(cornerRadius: 14))
        if look.costume != nil && tab.isAvailable && tab != .set {
            Text("한 벌 의상을 입고 있어요. 아이템을 고르면 개별 코디로 돌아가요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if tab.isAvailable && tab != .set && look.costume == nil {
            if tab == .top && look.top == .postech {
                Text("포스텍 과잠은 원래 색상과 로고를 유지해요.").font(.footnote).foregroundStyle(Color("OiDark"))
            } else { colorPicker }
        }
        Text("드래그로 돌려보세요. 옷에 맞는 오이가 함께 선택돼요.")
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        Text("꾸민 모습은 이 기기의 초안·카드 미리보기에 보관돼요. 지도·AR 공개에는 기존 오이 프리셋이 사용돼요.")
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        if !assets.filter({ $0.kind == "cucumber" }).isEmpty {
            DisclosureGroup("지도·AR 공개 프리셋") {
                Picker("공개 오이", selection: $draft.cucumberAsset) {
                    ForEach(assets.filter { $0.kind == "cucumber" }) { asset in Text(asset.name).tag(asset.id) }
                }.pickerStyle(.menu)
            }.font(.footnote).tint(Color("OiGreen"))
        }
        if let slot = selectedPhotoSlot { photoControls(slot) }
    }

    private var selectedPhotoSlot: OiPhotoSlot? {
        let slot: OiPhotoSlot? = tab == .top ? .top : tab == .bottom ? .bottom : tab == .set && look.costume != nil ? .top : nil
        return slot?.supports(look) == true ? slot : nil
    }
    private func photoControls(_ slot: OiPhotoSlot) -> some View {
        let design = look.artwork.designs[slot.itemID(in: look)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    photoScene.editPhotos(in: slot, look: look)
                    onPhotoEditingChanged(true)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { photoSlot = slot }
                } label: {
                    Label(design == nil ? "사진으로 옷 꾸미기" : "사진 디자인 수정 · \(design?.layers.count ?? 0)장", systemImage: "photo.badge.plus")
                        .font(CampusStyle.semibold(15)).frame(maxWidth: .infinity, minHeight: 36)
                }.buttonStyle(.borderedProminent).tint(Color("OiGreen")).accessibilityIdentifier("oi.wardrobe.photo.edit")
                if design != nil {
                    Button("지우기", role: .destructive) {
                        change { try? $0.artwork.set(nil, for: slot.itemID(in: look)) }
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
            case .pose, .hat, .accessory, .special:
                EmptyView()
            case .top:
                ForEach(OiWardrobeLook.Top.allCases, id: \.self) { top in
                    item(top.title, image: "oi-thumb-\(top.rawValue)", selected: look.costume == nil && look.top == top, id: top.rawValue) {
                        change { $0.top = top; $0.costume = nil }
                    }
                }
            case .bottom:
                ForEach(OiWardrobeLook.Bottom.allCases, id: \.self) { bottom in
                    item(bottom.title, image: "oi-thumb-\(bottom == .long ? "long-pants" : "shorts")", selected: look.costume == nil && look.bottom == bottom, id: bottom.rawValue) {
                        change { $0.bottom = bottom; $0.costume = nil }
                    }
                }
            case .shoes:
                item("흰 운동화", image: "oi-thumb-sneakers", selected: look.costume == nil, id: "sneakers") {
                    change { $0.shoeColor = 0xFFFFFF; $0.costume = nil }
                }
            case .set:
                ForEach(OiWardrobeLook.Costume.allCases) { costume in
                    item(costume.title, image: costume.thumbnailName, selected: look.costume == costume, id: "set-" + costume.rawValue) {
                        change { $0.costume = costume }
                    }
                }
                item("포스텍 과잠 세트", image: "oi-look-postech", selected: look.costume == nil && look.top == .postech && look.bottom == .long, id: "set-postech") {
                    var replacement = OiWardrobeLook()
                    replacement.top = .postech
                    replacement.artwork = look.artwork; replacement.fabrics = look.fabrics
                    customization.wardrobe = replacement
                }
            }
        }
        }
    }

    private func item(_ title: String, image: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if let url = Bundle.main.url(forResource: image, withExtension: "png") ?? Bundle.main.url(forResource: image, withExtension: "jpg"), let thumbnail = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: thumbnail).resizable().scaledToFit().frame(height: 68)
                } else {
                    Image(systemName: "tshirt").font(.system(size: 30)).frame(height: 68)
                }
                Text(title).font(CampusStyle.body(10)).lineLimit(2).frame(minHeight: 26)
            }.padding(5).frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color("OiGreen") : .clear, lineWidth: 2) }
                .overlay(alignment: .topTrailing) {
                    if selected { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Color("OiGreen")).padding(5).accessibilityHidden(true) }
                }
        }.buttonStyle(.plain).foregroundStyle(Color("OiDark"))
            .accessibilityIdentifier("oi.wardrobe.item.\(id)")
            .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(tab.rawValue) 색상").font(CampusStyle.semibold(15))
                Spacer()
                Text(selectedColorName).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)) {
                ForEach(colors, id: \.1) { name, rgb in
                    Button { selectColor(rgb) } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(UIColor(wardrobeRGB: rgb)))
                                .overlay { Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1) }
                                .overlay { if currentFabric == nil && currentColor == rgb { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(rgb == 0x555957 ? .white : Color("OiDark")) } }
                                .frame(width: 34, height: 34)
                            Text(name).font(.system(size: 10)).foregroundStyle(Color("OiDark"))
                        }.frame(maxWidth: .infinity, minHeight: 54)
                    }.buttonStyle(.plain).accessibilityLabel("\(tab.rawValue) \(name)")
                        .accessibilityIdentifier("oi.wardrobe.color.\(name)")
                        .accessibilityAddTraits(currentFabric == nil && currentColor == rgb ? .isSelected : [])
                }
            }
            if let slot = selectedPhotoSlot {
                Text("데님 텍스처").font(CampusStyle.semibold(15))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)) {
                    ForEach(OiDenim.allCases) { fabric in
                        Button { change { $0.fabrics[slot.itemID(in: look)] = fabric } } label: {
                            VStack(spacing: 4) {
                                if let image = OiPhotoRenderer.fabricImage(fabric) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 38, height: 38)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                        .overlay {
                                            if currentFabric == fabric {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color("OiGreen"))
                                            }
                                        }
                                }
                                Text(fabric.title).font(.system(size: 10))
                            }.frame(maxWidth: .infinity, minHeight: 56)
                        }.buttonStyle(.plain).foregroundStyle(Color("OiDark"))
                            .accessibilityLabel("\(tab.rawValue) \(fabric.title) 데님")
                            .accessibilityIdentifier("oi.wardrobe.denim.\(fabric.rawValue)")
                            .accessibilityAddTraits(currentFabric == fabric ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: 12) {
                ColorPicker("직접 색상 선택", selection: customColor, supportsOpacity: false)
                    .labelsHidden().frame(width: 44, height: 44)
                    .accessibilityLabel("\(tab.rawValue) 직접 색상 선택")
                    .accessibilityIdentifier("oi.wardrobe.color.custom")
                VStack(alignment: .leading, spacing: 3) {
                    Text("직접 색상 선택").font(CampusStyle.semibold(14))
                    Text("RGB 0–255 · #" + String(format: "%06X", currentColor))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

        }
    }
    private static let neutral: [(String, UInt32)] = [("화이트", 0xFFFFFF), ("아이보리", 0xF2EBDD), ("오트밀", 0xD7CBB8), ("토프", 0xB2A398), ("스톤", 0xB9BFBA), ("차콜", 0x555957)]
    private static let pastel: [(String, UInt32)] = [("세이지", 0xC6D8C2), ("민트", 0xC2DED3), ("스카이", 0xC5DBEC), ("라벤더", 0xD6CCE8), ("블러시", 0xEDCCD2), ("버터", 0xF1E3B2)]
    private var colors: [(String, UInt32)] { Self.neutral + Self.pastel }
    private var currentColor: UInt32 { tab == .bottom ? look.bottomColor : tab == .shoes ? look.shoeColor : look.topColor }
    private var selectedColorName: String { currentFabric.map { $0.title + " 데님" } ?? colors.first { $0.1 == currentColor }?.0 ?? "직접 선택" }
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
        change { value in
            if let slot = selectedPhotoSlot { value.fabrics.removeValue(forKey: slot.itemID(in: value)) }
            switch tab {
            case .top: value.topColor = rgb
            case .bottom: value.bottomColor = rgb
            case .shoes: value.shoeColor = rgb
            case .set, .pose, .hat, .accessory, .special: break
            }
        }
    }
    private func change(_ action: (inout OiWardrobeLook) -> Void) {
        var value = look; action(&value); customization.wardrobe = value
    }
}
