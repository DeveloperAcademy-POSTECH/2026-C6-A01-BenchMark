import SwiftUI
import UIKit

private enum OiOutfitTab: String, CaseIterable { case pose = "포즈", top = "상의", bottom = "하의", hat = "모자", set = "세트" }
private enum OiCardTab: String, CaseIterable { case size = "크기", background = "배경", pattern = "패턴", border = "테두리", set = "세트" }

struct OiCucumberCustomizationStep: View {
    @Binding var draft: OiStoryDraft
    @Binding var customization: OiDraftCustomization
    let assets: [OiAsset]
    var canContinue = true
    var onContinue: (() -> Void)?
    @State private var tab: OiOutfitTab = .set
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                TextField("오이 이름 입력", text: $draft.cucumberName).accessibilityIdentifier("oi.draft.cucumberName")
                Image(systemName: "pencil").accessibilityHidden(true)
            }.font(.custom("Paperlogy-3Light", size: 18, relativeTo: .body)).foregroundStyle(Color("OiGreen"))
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color("OiSoft"), in: Capsule()).frame(maxWidth: 225)
            ZStack(alignment: .bottomTrailing) {
                OiCreationCharacterImage(asset: draft.cucumberAsset).frame(height: 250).frame(maxWidth: .infinity)
                if let onContinue {
                    OiCreationDoneButton(enabled: canContinue, action: onContinue)
                        .accessibilityIdentifier("oi.creation.next")
                        .accessibilityHint("카드 꾸미기 단계로 이동합니다")
                }
            }.padding(.bottom, 16)
            tabs
            if tab == .set {
                OiCreationAssetPicker(assets: assets.filter { $0.kind == "cucumber" }, selection: $draft.cucumberAsset)
            } else {
                OiEmptyCustomizationGrid(title: "\(tab.rawValue) 아이템 준비 중")
                if tab == .top || tab == .bottom || tab == .hat {
                    ColorPicker("\(tab.rawValue) 색상 미리 선택", selection: colorBinding, supportsOpacity: false)
                    Text("색상 선택은 기기에 보관돼요. 옷이 준비되면 캐릭터에 적용할 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("현재는 준비된 오이 세트를 선택할 수 있어요. 개별 의상·포즈는 추후 추가돼요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(OiOutfitTab.allCases, id: \.self) { item in
                    OiCustomizationTabButton(title: item.rawValue, selected: tab == item) { tab = item }
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
        }
    }
    private var colorBinding: Binding<Color> {
        Binding(get: { Color(oiRGB: customization.garmentColors[tab.rawValue] ?? 0x708C40) },
                set: { customization.garmentColors[tab.rawValue] = $0.oiRGB })
    }
}

struct OiCardCustomizationStep: View {
    @Binding var draft: OiStoryDraft
    @Binding var customization: OiDraftCustomization
    let assets: [OiAsset]
    var canContinue = true
    var onContinue: (() -> Void)?
    @State private var tab: OiCardTab = .background
    var body: some View {
        VStack(spacing: 22) {
            ZStack(alignment: .bottomTrailing) {
                OiDraftCardPreview(draft: draft, customization: customization).frame(height: 283).frame(maxWidth: .infinity)
                if let onContinue {
                    OiCreationDoneButton(enabled: canContinue, action: onContinue)
                        .accessibilityIdentifier("oi.creation.next")
                        .accessibilityHint("공개 검토를 요청하기 전에 내용을 확인합니다")
                }
            }.padding(.bottom, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(OiCardTab.allCases, id: \.self) { item in
                        OiCustomizationTabButton(title: item.rawValue, selected: tab == item) { tab = item }
                            .accessibilityAddTraits(tab == item ? .isSelected : [])
                    }
                }
            }
            switch tab {
            case .background:
                Picker("배경 채우기", selection: $customization.fill) {
                    Text("단색").tag(OiDraftCustomization.Fill.solid)
                    Text("그라데이션").tag(OiDraftCustomization.Fill.gradient)
                }.pickerStyle(.segmented)
                ColorPicker("첫 번째 색", selection: color(\.firstColor), supportsOpacity: false)
                if customization.fill == .gradient {
                    ColorPicker("두 번째 색", selection: color(\.secondColor), supportsOpacity: false)
                }
                Toggle("카드에 오이 표시", isOn: $customization.showsCharacter).tint(Color("OiGreen"))
            case .set:
                Text("공개 카드 프리셋").font(.headline)
                OiCreationAssetPicker(assets: assets.filter { $0.kind == "card" }, selection: $draft.cardAsset, draft: draft)
            case .size, .pattern, .border:
                OiEmptyCustomizationGrid(title: "\(tab.rawValue) 옵션 준비 중")
            }
            Text("색상·그라데이션은 이 기기의 미리보기예요. 공개 카드에는 ‘세트’에서 선택한 프리셋이 적용돼요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func color(_ key: WritableKeyPath<OiDraftCustomization, UInt32>) -> Binding<Color> {
        Binding(get: { Color(oiRGB: customization[keyPath: key]) }, set: { customization[keyPath: key] = $0.oiRGB })
    }
}

private struct OiCustomizationTabButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(CampusStyle.medium(18)).tracking(0.36)
                .padding(.horizontal, 20).frame(minWidth: 72, minHeight: 44)
                .foregroundStyle(selected ? Color("OiDark") : .primary)
                .background(selected ? Color("OiBorder") : Color(white: 0.953), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

struct OiDraftCardPreview: View {
    let draft: OiStoryDraft
    let customization: OiDraftCustomization
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.cucumberName.isEmpty ? "나의 오이" : draft.cucumberName).font(CampusStyle.semibold(18)).lineLimit(1)
                .padding(6).background(.regularMaterial, in: Capsule())
            if customization.showsCharacter {
                OiCreationCharacterImage(asset: draft.cucumberAsset).frame(maxHeight: .infinity)
            } else { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.isEmpty ? "오래 남는 나의 이야기" : draft.title).font(.headline).lineLimit(2)
                Text(draft.body).font(.caption).lineLimit(2)
                Text([draft.theme, draft.emotion].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12).aspectRatio(180 / 283, contentMode: .fit)
        .background(LinearGradient(colors: [Color(oiRGB: customization.firstColor), Color(oiRGB: customization.fill == .solid ? customization.firstColor : customization.secondColor)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.6), lineWidth: 2) }
        .accessibilityElement(children: .combine).accessibilityLabel("카드 색상 미리보기, \(draft.cucumberName), \(draft.title)")
    }
}

struct OiCreationCharacterImage: View {
    let asset: String
    var body: some View {
        if UIImage(named: asset) != nil {
            Image(asset == "OiCats" ? "OiCatsPortrait" : asset).resizable().scaledToFit().accessibilityLabel("선택한 오이")
        } else {
            ContentUnavailableView("오이 미리보기 준비 중", systemImage: "leaf")
        }
    }
}

private struct OiEmptyCustomizationGrid: View {
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 8) {
                ForEach(0..<12) { _ in Rectangle().fill(Color(white: 0.851)).frame(height: 90).accessibilityHidden(true) }
            }
        }.padding(16).background(Color(white: 0.937))
    }
}

private struct OiCreationAssetPicker: View {
    let assets: [OiAsset]
    @Binding var selection: String
    var draft: OiStoryDraft?
    var body: some View {
        if assets.isEmpty {
            Text("선택 가능한 프리셋을 불러오는 중이에요. 연결을 확인해 주세요.").font(.footnote).foregroundStyle(.secondary)
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

private extension Color {
    init(oiRGB: UInt32) {
        self.init(red: Double((oiRGB >> 16) & 255) / 255, green: Double((oiRGB >> 8) & 255) / 255, blue: Double(oiRGB & 255) / 255)
    }
    var oiRGB: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((max(0, min(1, r)) * 255).rounded()) << 16 | UInt32((max(0, min(1, g)) * 255).rounded()) << 8 | UInt32((max(0, min(1, b)) * 255).rounded())
    }
}
