import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum OiCardTab: String, CaseIterable {
    case content = "내용", background = "배경", logo = "로고", stamp = "스탬프", size = "이미지"
}

struct OiCardCustomizationStep: View {
    @Binding var draft: OiStoryDraft
    @Binding var customization: OiDraftCustomization
    var donorName = ""
    var academicAuthor = ""
    var storyPhotos: [OiEditingPhoto] = []
    var loadStoryPhoto: ((OiEditingPhoto) async throws -> Data)? = nil
    var canContinue = true
    var isFinished = false
    var onContinue: (() -> Void)?
    var onSizeEditingChanged: ((Bool) -> Void)? = nil
    @State private var showingBack = false
    @State private var tab: OiCardTab = .content
    @State private var customBackground = false
    @State private var portrait: UIImage?
    @State private var portraitFailed = false
    @State private var captureAttempt = 0
    @State private var wardrobeKey: String?
    @State private var orientation = OiCardOrientation()
    @State private var showingPhotoEditor = false
    @State private var showingAttachments = false
    @State private var showingExport = false
    @State private var nameInput = ""
    @FocusState private var editingName: Bool
    @FocusState private var editingCaption: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var design: OiCardDesign { customization.card ?? OiCardDesign() }
    private var style: OiPostcardBackgroundStyle {
        design.postcardBackground ?? OiPostcardBackgroundStyle(color: design.borderFirst, fill: design.borderFill)
    }
    private var portraitKey: String? { wardrobeKey.map { $0 + "-angle-" + orientation.cacheIdentity } }
    private var needsPortrait: Bool {
        customization.showsCharacter && portraitKey != nil && (design.portraitKey != portraitKey || design.portraitPNG == nil)
    }
    private var isSizeEditing: Bool { tab == .size && !isFinished }

    var body: some View {
        GeometryReader { geometry in
            let previewHeight = min(308.0, max(180.0, geometry.size.height * 0.47))
            VStack(spacing: 0) {
                preview(height: previewHeight).padding(.horizontal, 20).padding(.bottom, 26)
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
                            let paperHeight = max(1, min(editor.size.height - 50, (editor.size.width - 80) * 502 / 362))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(customization.showsCharacter ? "캐릭터를 눌러 선택한 뒤\n드래그·핀치로 배치하세요." : "이미지를 눌러 선택한 뒤\n드래그·핀치로 배치하세요.")
                                    .font(CampusStyle.body(10)).foregroundStyle(Color("OiGreen"))
                                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
                                ZStack {
                                    OiPostcardBackground(style: style)
                                        .frame(width: paperHeight * 362 / 502, height: paperHeight).mask(OiPostcardPaper())
                                    placementEditor(height: paperHeight * 436 / 502)
                                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .background(Color(white: 0.67).ignoresSafeArea(edges: .bottom))
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                controls
                                storageDetails.padding(.top, 12)
                            }.padding(.horizontal, 20).padding(.bottom, 24)
                        }.scrollDismissesKeyboard(.interactively)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAttachments) { attachmentPicker }
        .sheet(isPresented: $showingPhotoEditor) {
            OiCardBackgroundPhotoEditor(design: cardBinding)
                .presentationDetents([.height(410)]).presentationDragIndicator(.hidden)
                .presentationCornerRadius(35).presentationBackground(Color("OiLight"))
        }
        .sheet(isPresented: $showingExport) {
            OiCardExportSheet {
                let card = try OiDraftCardPreview(draft: draft, customization: customization,
                    donorName: donorName, portrait: portrait).publication(colorScheme: .light)
                return try OiCardExportImages(card)
            }
        }
        .onAppear {
            prepareBackground()
            if design.postcardDate == nil { change { $0.postcardDate = Date() } }
            refreshPortrait(); nameInput = baseName; onSizeEditingChanged?(isSizeEditing)
        }
        .onChange(of: customization.wardrobe) { _, _ in refreshPortrait() }
        .onChange(of: tab) { _, _ in saveOrientation(); editingName = false; editingCaption = false }
        .onChange(of: isSizeEditing) { _, editing in onSizeEditingChanged?(editing) }
        .onDisappear { saveOrientation(); onSizeEditingChanged?(false) }
        .onChange(of: editingName) { _, focused in if !focused { commitName() } }
        .onChange(of: isFinished) { _, finished in if finished { editingName = false; commitName() } }
    }

    private func preview(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            OiDraftCardPreview(draft: draft, customization: customization, donorName: donorName,
                               portrait: portrait, showingBack: showingBack)
                .frame(width: height * 362 / 502, height: height)
                .overlay {
                    if needsPortrait, (tab != .size || isFinished), let look = customization.wardrobe {
                        OiCardPortraitCapture(look: look, cacheKey: portraitKey ?? "", orientation: orientation,
                            onCapture: acceptPortrait, onFailure: { portraitFailed = true })
                            .id(captureAttempt).aspectRatio(332 / 472, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .opacity(0.001).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .top) {
                    if needsPortrait && tab != .size {
                        Group {
                            if portraitFailed { Button("오이 이미지 다시 만들기") { portraitFailed = false; captureAttempt += 1 } }
                            else { ProgressView("오이를 엽서에 담는 중") }
                        }.font(CampusStyle.body(11)).padding(8).background(.regularMaterial, in: Capsule())
                    }
                }
            HStack(alignment: .bottom) {
                VStack(spacing: 3) {
                    Text("오이").font(CampusStyle.semibold(16))
                    VStack(spacing: 0) {
                        faceButton("앞", back: false)
                        faceButton("뒤", back: true)
                    }.padding(2).background(Color(white: 0.85), in: Capsule())
                }
                Spacer()
                if let onContinue {
                    Button { editingName = false; editingCaption = false; commitName(); onContinue() } label: {
                        Text(isFinished ? "다시 꾸미기" : "완료").underline().font(CampusStyle.body(16))
                            .padding(.horizontal, 16).padding(.vertical, 6).background(Color("OiBorder"), in: Capsule())
                    }.buttonStyle(OiCreationPressStyle()).foregroundStyle(.black)
                        .disabled(!canContinue || needsPortrait).accessibilityIdentifier("oi.customization.done")
                }
            }
        }.frame(maxWidth: .infinity).frame(height: height)
    }
    private func faceButton(_ title: String, back: Bool) -> some View {
        Button { showingBack = back } label: {
            Text(title).font(showingBack == back ? CampusStyle.semibold(10) : CampusStyle.body(10))
                .frame(width: 30, height: 42).background(showingBack == back ? Color.white : .clear, in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(.black).accessibilityLabel("카드 \(back ? "뒷면" : "앞면")")
            .accessibilityAddTraits(showingBack == back ? .isSelected : []).accessibilityIdentifier("oi.postcard.side.\(back ? "back" : "front")")
    }
    @ViewBuilder private var tabs: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal) { tabButtons }.scrollIndicators(.hidden)
        } else { tabButtons }
    }
    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(OiCardTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    Text(item.rawValue).font(tab == item ? .custom("Paperlogy-7Bold", size: 16, relativeTo: .body) : CampusStyle.medium(16))
                        .foregroundStyle(tab == item ? Color("OiGreen") : Color(white: 0.44))
                        .frame(minWidth: 39).frame(height: 40)
                        .overlay(alignment: .bottom) {
                            if tab == item { Color("OiGreen").frame(width: 39, height: 2).padding(.bottom, 3) }
                        }
                }.buttonStyle(.plain).accessibilityIdentifier("oi.card.tab.\(item.rawValue)")
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                if item != OiCardTab.allCases.last {
                    if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 24) }
                    else { Spacer(minLength: 0) }
                }
            }
        }
    }
    @ViewBuilder private var controls: some View {
        switch tab {
        case .content: contentEditor
        case .background: backgroundEditor
        case .logo: logoEditor
        case .stamp: stampEditor
        case .size: EmptyView()
        }
    }
    private func placementEditor(height: CGFloat) -> some View {
        OiCardPlacementEditor(image: customization.showsCharacter ? portrait : design.backgroundPhoto.flatMap(UIImage.init(data:)),
            placement: customization.showsCharacter ? designBinding(\.characterPlacement) : designBinding(\.backgroundPlacement),
            frameHeight: height, compact: true, minimalChrome: true,
            backdropColor: customization.showsCharacter && design.usesCharacterBackdrop
                ? OiPostcardCharacterBackdrop.color(for: design) : nil,
            look: customization.showsCharacter ? customization.wardrobe : nil,
            orientation: customization.showsCharacter && customization.wardrobe != nil ? $orientation : nil,
            portraitKey: portraitKey ?? "", onCapture: acceptPortrait, onInteractionEnded: saveOrientation)
    }
    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 35) {
                    Text("이미지").font(CampusStyle.medium(16))
                    HStack(spacing: 20) {
                        choice("첨부한 이미지", selected: !customization.showsCharacter) {
                            customization.showsCharacter = false
                            if !storyPhotos.isEmpty && loadStoryPhoto != nil { showingAttachments = true }
                            else { showingPhotoEditor = true }
                        }.accessibilityIdentifier("oi.postcard.source.photo")
                        choice("오이 이미지", selected: customization.showsCharacter) { customization.showsCharacter = true }
                            .accessibilityIdentifier("oi.postcard.source.cucumber")
                    }
                }
                Text("우표 위의 이미지 또는 오이캐릭터의 크기는 위의 ‘이미지’ 탭에서 조정할 수 있습니다")
                    .font(CampusStyle.body(10)).foregroundStyle(Color(white: 0.67)).fixedSize(horizontal: false, vertical: true)
            }.frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 20, alignment: .top)
            VStack(alignment: .leading, spacing: 6) {
                Text("내용").font(CampusStyle.medium(16))
                VStack(alignment: .leading, spacing: 6) {
                    TextField("엽서에 남길 이야기", text: OiStoryWritingStep.limitedStoryText($draft.body), axis: .vertical)
                        .lineLimit(3...5).font(CampusStyle.body(16)).lineSpacing(5).focused($editingCaption)
                        .accessibilityIdentifier("oi.card.caption")
                    HStack {
                        Text("\(draft.body.utf8.count) / 1,500byte").foregroundStyle(Color(white: 0.67))
                        Spacer()
                        Button(editingCaption ? "완료" : "수정") { editingCaption.toggle() }.underline().tint(Color("OiGreen"))
                    }.font(CampusStyle.body(10))
                }.padding(.horizontal, 20).padding(.vertical, 16)
                    .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 30))
                Text("줄바꿈 및 띄어쓰기를 조절해주세요! 내용이 너무 튀어나오지 않는지 확인해서 수정해주세요!")
                    .font(CampusStyle.body(10)).foregroundStyle(Color(white: 0.67)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 35) {
                Text("기부자").font(CampusStyle.medium(16))
                HStack(spacing: 14) {
                    authorChoice("익명", mode: "anonymous")
                    authorChoice("학과, 학번만", mode: "academic")
                    authorChoice("실명", mode: "name")
                }
            }
            if style.authorMode == "academic", academicAuthor.isEmpty {
                Text("계정에 공개할 학과와 학번을 등록하면 선택할 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("오이 이름").font(CampusStyle.medium(16))
                HStack {
                    TextField("다섯 글자 이내", text: $nameInput).focused($editingName)
                        .submitLabel(.done).onSubmit { editingName = false }.accessibilityIdentifier("oi.draft.cucumberName")
                    Text("오이").foregroundStyle(.secondary)
                }.font(CampusStyle.body(16)).padding(16).background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 16))
                if nameInput.count > 5 { Text("다섯 글자까지 입력할 수 있어요.").font(.caption).foregroundStyle(.red) }
            }
        }.foregroundStyle(.black)
    }
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).stroke(.black, lineWidth: 1).frame(width: 20, height: 20)
                    if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                }
                Text(title).font(CampusStyle.body(17)).fixedSize()
            }.frame(minHeight: 30)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func authorChoice(_ title: String, mode: String) -> some View {
        choice(title, selected: (style.authorMode ?? "name") == mode) {
            updateBackground { $0.authorMode = mode }
            change { $0.postcardAcademicAuthor = mode == "academic" ? academicAuthor : nil }
        }.disabled(mode == "academic" && academicAuthor.isEmpty || mode == "name" && donorName.isEmpty)
            .accessibilityIdentifier("oi.card.author.\(mode)")
    }
    private func prepareBackground() {
        if customization.card == nil {
            var value = OiCardDesign()
            value.postcardLayoutVersion = 2
            value.postcardBackground = .init(color: 0xD9D9D9, fill: .solid)
            customization.card = value
        } else if design.postcardBackground == nil {
            change { $0.postcardBackground = .init(color: $0.borderFirst, fill: $0.borderFill) }
        }
        customBackground = style.middleColor != nil || style.endColor != nil
    }
    private func updateBackground(_ edit: (inout OiPostcardBackgroundStyle) -> Void) {
        var value = style; edit(&value)
        change { $0.postcardBackground = value; $0.borderFirst = value.color; $0.borderFill = value.fill }
    }
    var backgroundEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("배경", selection: $customBackground) {
                Text("스탠다드").tag(false)
                Text("커스텀").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("oi.postcard.background.mode")
            characterBackdropControls
            if customBackground { customColors }
            else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                    ForEach(OiPostcardPreset.allCases) { preset in
                        Button {
                            updateBackground { $0.preset = preset.rawValue; $0.color = preset.color; $0.middleColor = nil; $0.endColor = nil; $0.fill = .gradient }
                            change { $0.postcardLayoutVersion = 2 }
                        } label: {
                            VStack(spacing: 5) {
                                Image(preset.swatch).resizable().scaledToFit().frame(height: 111)
                                    .overlay { if style.preset == preset.rawValue { RoundedRectangle(cornerRadius: 2).stroke(Color("OiGreen"), lineWidth: 2) } }
                                Text(preset.title).font(CampusStyle.body(14)).foregroundStyle(Color(white: 0.19))
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityLabel(preset.title)
                            .accessibilityAddTraits(style.preset == preset.rawValue ? .isSelected : [])
                    }
                }
            }
        }.tint(Color("OiGreen"))
    }
    private var characterBackdropControls: some View {
        let color = OiPostcardCharacterBackdrop.color(for: design)
        let available = customization.showsCharacter && !showingBack
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle(isOn: Binding(get: { design.usesCharacterBackdrop }, set: { enabled in
                    change { $0.characterBackdropEnabled = enabled }
                })) {
                    Text("오이 뒤 배경 넣기").font(CampusStyle.medium(14))
                }.disabled(!available)
                    .accessibilityIdentifier("oi.card.character.backdrop.toggle")
                OiPostcardColorRing(title: "오이 뒤 배경", color: Binding(
                    get: { OiPostcardCharacterBackdrop.color(for: design) },
                    set: { color in change { $0.characterBackdropColor = color } }), pickerHeight: 300,
                    onReset: { change { $0.characterBackdropColor = nil } })
                    .overlay { Circle().fill(Color(oiRGB: color)).frame(width: 18, height: 18).allowsHitTesting(false) }
                    .disabled(!available || !design.usesCharacterBackdrop)
                    .opacity(available && design.usesCharacterBackdrop ? 1 : 0.4)
                    .accessibilityIdentifier("oi.card.character.backdrop.color")
            }
            HStack(spacing: 8) {
                Text(design.characterBackdropColor == nil ? "종이색에 맞춘 자동 색상" : "직접 선택한 색상")
                Text(String(format: "#%06X", color)).monospacedDigit()
                Spacer(minLength: 0)
                if design.characterBackdropColor != nil {
                    Button("자동 색상") { change { $0.characterBackdropColor = nil } }
                        .underline().frame(minHeight: 32)
                        .disabled(!available || !design.usesCharacterBackdrop)
                        .accessibilityIdentifier("oi.card.character.backdrop.automatic")
                }
            }.font(CampusStyle.body(11)).foregroundStyle(.secondary)
        }
    }
    private var customColors: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 362
            ZStack(alignment: .topLeading) {
                Text("직접 색상 선택").font(CampusStyle.semibold(16)).offset(x: 8, y: 18)
                Image("OiPostcardDiagram-imgVector40").resizable().frame(width: 139, height: 216.5).offset(x: 14, y: 50)
                ForEach(0..<3) { index in
                    let x: CGFloat = [127, 74, 18][index]
                    let y: CGFloat = [63, 148, 235][index]
                    let widths: CGFloat = [54,108,164][index]
                    Image("OiPostcardDiagram-imgVector\([43,41,42][index])").resizable()
                        .frame(width: widths, height: 1).offset(x: x + 10, y: y + 10)
                    Image(index == 1 ? "OiPostcardDiagram-imgEllipse44" : "OiPostcardDiagram-imgEllipse45")
                        .resizable().frame(width: 20, height: 20)
                        .overlay { Circle().fill(Color(oiRGB: selectedColor(index))).padding(1) }
                        .offset(x: x, y: y).accessibilityHidden(true)
                    colorControl(index).offset(x: 190, y: [52.0,138,225][index])
                }
            }.frame(width: 362, height: 282, alignment: .topLeading).scaleEffect(scale, anchor: .topLeading)
        }.frame(height: 282)
    }
    private func selectedColor(_ index: Int) -> UInt32 {
        let colors = style.customColors
        return index == 0 ? colors.start : index == 1 ? colors.middle : colors.end
    }
    private func colorControl(_ index: Int) -> some View {
        let value = selectedColor(index)
        return HStack(spacing: 10) {
            OiPostcardColorRing(title: ["시작", "중간", "끝"][index], color: Binding(get: { selectedColor(index) }, set: { color in
                updateBackground { $0.setCustomColor(color, at: index) }
                change { $0.postcardLayoutVersion = 2 }
            })).accessibilityIdentifier("oi.card.background.picker.\(index)")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(["시작", "중간", "끝"][index]) Color").font(CampusStyle.semibold(13)).foregroundStyle(Color(white: 0.19))
                Text(String(format: "RGB 0-255 #%06X", value)).font(CampusStyle.body(10)).foregroundStyle(Color(white: 0.66))
            }
        }.accessibilityIdentifier("oi.card.background.color.\(index)")
    }
    @ViewBuilder private var logoEditor: some View {
        if showingBack { backLogoEditor }
        else { frontLogoEditor }
    }
    private var backLogoEditor: some View {
        let color = OiPostcardBackLogoStyle.color(for: style)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 24) {
                OiPostcardPostechLogo(color: color).frame(width: 144, height: 144)
                VStack(alignment: .leading, spacing: 12) {
                    Text("포스텍 로고 색상").font(CampusStyle.medium(16))
                    HStack(spacing: 10) {
                        OiPostcardColorRing(title: "포스텍 로고", color: Binding(
                            get: { OiPostcardBackLogoStyle.color(for: style) },
                            set: { color in updateBackground { $0.backLogoColor = color } }), pickerHeight: 360)
                            .accessibilityIdentifier("oi.card.back.logo.color")
                        Text(String(format: "#%06X", color)).font(CampusStyle.body(12)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("색상을 고르면 위 카드 뒷면에 바로 적용돼요.")
                .font(CampusStyle.body(12)).foregroundStyle(.secondary)
        }.padding(.top, 16)
    }
    private var frontLogoEditor: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(["white", "black"], id: \.self) { logo in
                Button { change { $0.postcardLayoutVersion = 2; $0.postcardLogo = $0.postcardLogo == logo ? nil : logo } } label: {
                    VStack(spacing: 10) {
                        GeometryReader { _ in
                            RoundedRectangle(cornerRadius: 20).fill(Color(white: logo == "white" ? 0.2 : 0.96))
                            Image("OiPostcardLogoSwatch-" + logo).resizable().frame(width: 20, height: 80)
                                .offset(x: 16, y: 114)
                        }.frame(height: 205).clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(white: 0.76), lineWidth: 2))
                            .overlay { if design.postcardLogo == logo { RoundedRectangle(cornerRadius: 20).stroke(Color("OiGreen"), lineWidth: 2) } }
                        Text(logo == "white" ? "White Logo" : "Black Logo").font(CampusStyle.medium(20)).foregroundStyle(Color(white: 0.19))
                    }
                }.buttonStyle(.plain).accessibilityLabel(logo == "white" ? "흰색 로고" : "검정색 로고")
            }
        }.padding(.top, 16)
    }
    private var stampEditor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(1...12, id: \.self) { number in
                    Button { change { $0.postcardLayoutVersion = 2; $0.postcardStamp = $0.postcardStamp == number ? nil : number } } label: {
                        Image("OiPostcardStamp-\(number <= 6 ? "white" : "black")\((number-1)%6+1)")
                            .resizable().scaledToFit().padding(.horizontal, 14).padding(.vertical, 8)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Color(white: number <= 6 ? 0.2 : 0.96), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(design.postcardStamp == number ? Color("OiGreen") : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityLabel("\(number <= 6 ? "흰색" : "검정색") 스탬프 \((number-1)%6+1)")
                }
            }
            Text("택 1").font(CampusStyle.body(12)).foregroundStyle(Color(white: 0.19))
        }
    }
    private var attachmentPicker: some View {
        NavigationStack {
            List {
                ForEach(Array(storyPhotos.enumerated()), id: \.element.id) { index, photo in
                    OiCardAttachmentOption(number: index + 1, load: { try await loadStoryPhoto?(photo) }) { bytes in
                        change { $0.backgroundPhoto = bytes; $0.backgroundPlacement = OiCardPlacement() }
                        showingAttachments = false
                    }
                }
            }.navigationTitle("첨부한 이미지").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showingAttachments = false } } }
        }
    }
    @ViewBuilder private var storageDetails: some View {
        Button("카드 이미지 저장·공유", systemImage: "square.and.arrow.up") { showingExport = true }
            .disabled(needsPortrait).accessibilityIdentifier("oi.card.export.open")
        DisclosureGroup("저장·공개 안내") {
            Text("기부자 선택은 카드에 표시할 정보만 바꿉니다. 이야기의 공개 작성자 정보는 계정 설정을 따릅니다. 꾸민 카드는 이 기기에 저장되며 공개 검토에서 양면을 함께 확인합니다.")
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
        }.font(.caption).tint(Color("OiGreen"))
    }
    #if DEBUG
    func tabForTest(_ title: String, custom: Bool = false, back: Bool = false) -> Self {
        var result = self
        result._tab = State(initialValue: OiCardTab(rawValue: title) ?? .content)
        result._customBackground = State(initialValue: custom)
        result._showingBack = State(initialValue: back)
        return result
    }
    #endif
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
