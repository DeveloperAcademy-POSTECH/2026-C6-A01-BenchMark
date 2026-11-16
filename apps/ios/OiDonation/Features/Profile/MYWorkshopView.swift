//
//  MYWorkshopView.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import SwiftUI

struct MYWorkshopView: View {
    let demo: MYLibraryStore
    var remote: OiRemoteStore?
    @State private var selectedTab: MYWorkshopTab
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    init(demo: MYLibraryStore, remote: OiRemoteStore? = nil, initialTab: MYWorkshopTab = .authored) {
        self.demo = demo
        self.remote = remote
        _selectedTab = State(initialValue: initialTab)
    }

    @ScaledMetric(relativeTo: .headline) private var profileLineHeight = 39.0
    @ScaledMetric(relativeTo: .body) private var academicLineHeight = 12.0

    private var isSignedIn: Bool { remote?.account != nil }
    private var usesExpandedLayout: Bool { dynamicTypeSize > .large }

    private func profileNeedsMoreRoom(width: CGFloat) -> Bool {
        let columnWidth = width * 211 / 402
        let nameFont = UIFont(name: "Paperlogy-7Bold", size: 26) ?? .boldSystemFont(ofSize: 26)
        let academicFont = UIFont(name: "Paperlogy-4Regular", size: 12) ?? .systemFont(ofSize: 12)
        return (profileTitle as NSString).size(withAttributes: [.font: nameFont, .kern: 0.52]).width > columnWidth
            || (academicTitle as NSString).size(withAttributes: [.font: academicFont, .kern: 0.24]).width > columnWidth - 16
    }
    private let profileBrown = Color(red: 80 / 255, green: 45 / 255, blue: 0)

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 402
            ScrollView {
                VStack(spacing: 0) {
                    if usesExpandedLayout || profileNeedsMoreRoom(width: geometry.size.width) {
                        expandedProfile
                    } else {
                        profileHeader(scale: scale)
                    }
                    VStack(spacing: 10) {
                        tabs
                        MYWorkshopContent(tab: selectedTab, demo: demo, remote: remote)
                    }
                    .padding(.leading, 21).padding(.trailing, 19)
                    .padding(.top, 6)
                    .padding(.bottom, 116)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(minHeight: max(300, geometry.size.height - 325 * scale), alignment: .top)
                    .background { panelBackground }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .circular))
                }
                .background(alignment: .top) {
                    if !usesExpandedLayout && !profileNeedsMoreRoom(width: geometry.size.width) {
                        // The room continues behind the paper's rounded top corners.
                        Image("MYProfileRoom").resizable()
                            .frame(width: geometry.size.width, height: 356 * scale)
                            .accessibilityHidden(true)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(red: 1, green: 247 / 255, blue: 225 / 255))
            .overlay(alignment: .bottomLeading) {
                exitButton.padding(.leading, 21)
                    .padding(.bottom, max(32, geometry.safeAreaInsets.bottom))
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.navigationStack)
        .onChange(of: remote?.account?.id) { _, _ in selectedTab = .authored }
    }

    private func profileHeader(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("MYProfileRoom").resizable()
                .frame(width: 402 * scale, height: 356 * scale)
                .accessibilityHidden(true)
            farmer
                .frame(width: 177.75 * scale, height: 237 * scale)
                .position(x: 301.875 * scale, y: 187.5 * scale)
            VStack(alignment: .leading, spacing: 0) {
                // Align Paperlogy optical baselines with the measured Figma text frames.
                academicLabel.frame(height: 12).offset(y: 1)
                profileName.frame(height: 39).offset(y: 4)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    unavailableCount("기부횟수")
                    unavailableCount("이어진 기부 횟수")
                }.padding(.top, 7)
            }
            .frame(width: 211 * scale, alignment: .leading)
            .padding(.leading, 28 * scale)
            .padding(.top, 90 * scale)
            inactiveCoin
                .position(x: 80.875 * scale, y: 277.771 * scale)
            if isSignedIn {
                Text("캐릭터를 눌러\n농부를 꾸며주세요!")
                    .font(.custom("Paperlogy-3Light", size: 12, relativeTo: .caption))
                    .tracking(0.24)
                    .lineHeight(.exact(points: 14.4))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Color(red: 232 / 255, green: 204 / 255, blue: 182 / 255))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 130, alignment: .trailing)
                    .position(x: 195 * scale, y: 262.6 * scale)
                    .allowsHitTesting(false)
            }
            settingsButton
                .padding(.trailing, 8.5 * scale)
                .padding(.top, 64 * scale)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 325 * scale, alignment: .top)
        .clipped()
    }

    private var expandedProfile: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsButton.frame(maxWidth: .infinity, alignment: .trailing)
            academicLabel
            profileName
            unavailableCount("기부횟수")
            unavailableCount("이어진 기부 횟수")
            farmer.frame(height: 237).frame(maxWidth: .infinity)
            if isSignedIn {
                Text("캐릭터를 눌러 농부를 꾸며주세요!")
                    .font(CampusStyle.body(16)).foregroundStyle(profileBrown)
            }
            inactiveCoin
        }
        .padding(.horizontal, 28).padding(.top, 64).padding(.bottom, 24)
        .background(alignment: .top) {
            Image("MYProfileRoom").resizable().scaledToFit().accessibilityHidden(true)
        }
        .background(Color(red: 1, green: 247 / 255, blue: 225 / 255))
    }

    private var academicLabel: some View {
        Label(academicTitle, systemImage: "graduationcap.fill")
            .labelStyle(MYAcademicLabelStyle())
            .font(CampusStyle.body(12)).tracking(0.24)
            .lineHeight(.exact(points: academicLineHeight))
            .foregroundStyle(Color(red: 143 / 255, green: 88 / 255, blue: 0))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("my.profile.academic")
    }

    private var academicTitle: String {
        guard isSignedIn, let profile = remote?.profile else { return "나만의 오이 이야기" }
        let school = remote?.schools.first { $0.id == profile.schoolId }?.name
        let title = [school, profile.department].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }.joined(separator: " ")
        return title.isEmpty ? "나만의 오이 이야기" : title
    }

    private var profileName: some View {
        Text(profileTitle)
            .font(CampusStyle.characterTitle(26)).tracking(0.52)
            .lineHeight(.exact(points: profileLineHeight))
            .foregroundStyle(profileBrown)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("my.profile.name")
    }

    private var profileTitle: String {
        guard isSignedIn, let profile = remote?.profile else { return "로그인해 주세요" }
        let publicName = profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = publicName.isEmpty ? (profile.farmName ?? "오이") : publicName
        guard let year = profile.admissionYear, !year.isEmpty else { return name }
        return "\(year.suffix(2))학번 \(name)"
    }

    private func unavailableCount(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(CampusStyle.medium(12))
                .foregroundStyle(Color(red: 80 / 255, green: 80 / 255, blue: 80 / 255))
            Text("—").font(CampusStyle.semibold(12)).foregroundStyle(CampusStyle.green)
        }
        .tracking(0.24).padding(.horizontal, 16).padding(.vertical, 8)
        .frame(minWidth: title == "기부횟수" ? 102 : 141)
        .background(.white, in: Capsule())
        .overlay { Capsule().strokeBorder(Color(red: 192 / 255, green: 156 / 255, blue: 126 / 255), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue("집계 미제공")
        .accessibilityHint("기부 집계를 제공하지 않습니다")
    }

    private var farmer: some View {
        NavigationLink {
            MYFarmerCustomizationView(remote: remote).id(remote?.account?.id)
        } label: {
            MYFarmerArtwork(ownerID: remote?.account?.id, outfit: remote?.farmerOutfit)
                .shadow(color: .white, radius: 7.5)
                .background(alignment: .bottom) {
                    Image("MYProfileFarmerShadow").resizable().scaledToFit()
                        .frame(width: 165.162, height: 48.144)
                        .offset(x: 15.576, y: 10)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!isSignedIn)
        .accessibilityLabel("\(remote?.profile?.farmName ?? "오이")의 농부 꾸미기")
        .accessibilityIdentifier("my.farmer.customize")
    }

    private var inactiveCoin: some View {
        HStack(spacing: 8.203) {
            Text("+").font(CampusStyle.characterTitle(20.508)).foregroundStyle(.white)
                .frame(width: 24.609, height: 24.609)
                .background(Color(red: 163 / 255, green: 140 / 255, blue: 33 / 255), in: Circle())
            HStack(spacing: 3.281) {
                Image("MYProfileCoin").resizable().scaledToFit().frame(width: 24.609, height: 24.609)
                Text("—pc").font(CampusStyle.medium(13.125)).tracking(0.2625)
                    .foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: usesExpandedLayout ? nil : 26.8)
            }
        }
        .padding(.leading, 5.742).padding(.trailing, 12.305).padding(.vertical, 4.922)
        .background(Color(red: 1, green: 249 / 255, blue: 223 / 255), in: Capsule())
        .overlay { Capsule().strokeBorder(Color(red: 163 / 255, green: 140 / 255, blue: 33 / 255), lineWidth: 0.82) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("피클코인").accessibilityValue("사용 불가")
        .accessibilityHint("코인 구매와 적립은 제공하지 않습니다")
        .accessibilityIdentifier("my.coin.unavailable")
    }

    private var settingsButton: some View {
        NavigationLink { MYSettingsView(demo: demo, remote: remote) } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.black).frame(width: 44, height: 44, alignment: .top)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("설정").accessibilityIdentifier("my.settings")
    }

    private var tabs: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 1) { tabButtons }
            VStack(spacing: 4) { tabButtons }
        }
    }

    private var tabButtons: some View {
        ForEach(MYWorkshopTab.allCases, id: \.self) { tab in
            Button { selectedTab = tab } label: {
                Text(tab.rawValue).font(CampusStyle.medium(16)).tracking(0.32)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(selectedTab == tab ? Color(white: 35 / 255) : Color(white: 157 / 255))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab { Rectangle().fill(Color(white: 0.5)).frame(height: 0.5).padding(.bottom, 6) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            .accessibilityIdentifier("my.tab.\(tab)")
        }
    }

    private var panelBackground: some View {
        GeometryReader { geometry in
            Image("MYProfilePaper").resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }

    private var exitButton: some View {
        Button { dismiss() } label: {
            Image("MYExitDoor").resizable().scaledToFit().frame(width: 50, height: 50)
                .frame(width: 66, height: 66).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color(red: 1, green: 188 / 255, blue: 96 / 255).opacity(0.35)).interactive(), in: Circle())
        .accessibilityLabel("MY 닫기").accessibilityIdentifier("my.close")
    }
}

private struct MYAcademicLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview("MY 기준", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack { MYWorkshopView(demo: MYLibraryStore()) }
}
#Preview("MY 작은 화면", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack { MYWorkshopView(demo: MYLibraryStore()) }
}
#Preview("MY 큰 화면", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack { MYWorkshopView(demo: MYLibraryStore()) }
}
