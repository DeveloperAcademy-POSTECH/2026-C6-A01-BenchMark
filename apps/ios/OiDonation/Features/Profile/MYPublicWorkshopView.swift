//
//  MYPublicWorkshopView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/17/26.
//

import SwiftUI

/// Public MY (Figma 5903:10783), backed only by the author's public profile and stories.
struct MYPublicWorkshopView: View {
    let authorID: UUID
    let remote: OiRemoteStore
    let store: CampusStoryStore

    private enum State {
        case loading
        case loaded(OiProfile, [OiLiveStory])
        case unavailable
        case failed
    }

    @State private var state = State.loading
    @State private var tab = MYWorkshopTab.authored
    @State private var loadID = UUID()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if OiContentSafetyStore.shared.isBlocked(authorID) {
                unavailable
            } else {
                switch state {
                case .loading:
                    ProgressView("공개 프로필 불러오는 중")
                case .loaded(let profile, let stories):
                    workshop(profile: profile, stories: stories)
                case .unavailable:
                    unavailable
                case .failed:
                    unavailable
                }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(remote.continuationPrivacyKey)/\(remote.revision)/\(scenePhase)") {
            guard scenePhase == .active else { return }
            await load()
        }
    }

    private var unavailable: some View {
        ContentUnavailableView("공개 프로필을 볼 수 없어요", systemImage: "person.crop.circle")
    }

    private func workshop(profile: OiProfile, stories: [OiLiveStory]) -> some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 402
            ScrollView {
                VStack(spacing: 0) {
                    header(profile: profile, scale: scale)
                    VStack(spacing: 10) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 1) { tabButtons }
                            VStack(spacing: 4) { tabButtons }
                        }
                        content(profile: profile, stories: stories)
                    }
                    .padding(.leading, 21).padding(.trailing, 19)
                    .padding(.top, 6).padding(.bottom, 34)
                    .frame(maxWidth: .infinity, minHeight: max(270, geometry.size.height - 325 * scale), alignment: .top)
                    .background {
                        GeometryReader { panel in
                            Image("MYProfilePaper").resizable().scaledToFill()
                                .frame(width: panel.size.width, height: panel.size.height).clipped()
                        }.accessibilityHidden(true)
                    }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
                }
                .background(alignment: .top) {
                    Image("MYProfileRoom").resizable()
                        .frame(width: geometry.size.width, height: 356 * scale)
                        .accessibilityHidden(true)
                }
                .background(Color(oiRGB: 0xFFF7E1))
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await load() }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func header(profile: OiProfile, scale: CGFloat) -> some View {
        let school = remote.schools.first { $0.id == profile.schoolId }?.name
        let academic = [school, profile.department].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }.joined(separator: " ")
        return Group {
            if dynamicTypeSize > .large {
                VStack(alignment: .leading, spacing: 16) {
                    identity(profile: profile, academic: academic)
                    farmer(profile).frame(height: 237).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28).padding(.top, 104).padding(.bottom, 24)
                .background(Color(oiRGB: 0xFFF7E1))
            } else {
                ZStack(alignment: .topLeading) {
                    farmer(profile)
                        .frame(width: 177.75 * scale, height: 237 * scale)
                        .position(x: 301.875 * scale, y: 187.5 * scale)
                    identity(profile: profile, academic: academic)
                        .frame(width: 211 * scale, alignment: .leading)
                        .padding(.leading, 28 * scale)
                        .padding(.top, max(104, 113 * scale))
                        .padding(.bottom, 10)
                }
                .frame(minHeight: max(325 * scale, 300), alignment: .topLeading)
            }
        }
    }

    private func identity(profile: OiProfile, academic: String) -> some View {
        let publicName = profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let year = profile.admissionYear?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = publicName.isEmpty || year.isEmpty ? profile.publicDonorLine : "\(year.suffix(2))학번 \(publicName)"
        return VStack(alignment: .leading, spacing: 6) {
            Label(academic.isEmpty ? "공개 프로필" : academic,
                  systemImage: academic.isEmpty ? "person.crop.circle.fill" : "graduationcap.fill")
                .font(CampusStyle.body(12)).tracking(0.24)
                .foregroundStyle(Color(oiRGB: 0x8F5800))
            Text(name).font(CampusStyle.characterTitle(26)).tracking(0.52)
                .foregroundStyle(Color(oiRGB: 0x502D00))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("my.public.name")
            VStack(alignment: .leading, spacing: 6) {
                metric("기부횟수")
                metric("이어진 기부 횟수")
            }.padding(.top, 22)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metric(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(Color(oiRGB: 0x505050))
            Text("—").foregroundStyle(CampusStyle.green)
        }
        .font(CampusStyle.medium(16)).tracking(0.32)
        .padding(.horizontal, 21.576).padding(.vertical, 10.788)
        .background(.white, in: Capsule())
        .overlay { Capsule().strokeBorder(Color(oiRGB: 0xC09C7E), lineWidth: 1.348) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue("집계 미제공")
    }

    private func farmer(_ profile: OiProfile) -> some View {
        MYPublicFarmerArtwork(asset: profile.farmerAsset)
            .shadow(color: .white, radius: 7.5)
            .background(alignment: .bottom) {
                Image("MYProfileFarmerShadow").resizable().scaledToFit()
                    .frame(width: 165.162, height: 48.144).offset(x: 15.576, y: 10)
                    .accessibilityHidden(true)
            }
    }

    private var tabButtons: some View {
        ForEach(MYWorkshopTab.allCases) { item in
            Button { tab = item } label: {
                Text(item.rawValue).font(CampusStyle.medium(16)).tracking(0.32)
                    .fixedSize()
                    .foregroundStyle(Color(oiRGB: tab == item ? 0x232323 : 0x686868))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .bottom) {
                        if tab == item { Rectangle().fill(Color(white: 0.5)).frame(height: 0.5).padding(.bottom, 6) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(tab == item ? .isSelected : [])
        }
    }

    @ViewBuilder private func content(profile: OiProfile, stories: [OiLiveStory]) -> some View {
        switch tab {
        case .authored:
            if stories.isEmpty {
                ContentUnavailableView("공개된 이야기가 없어요", systemImage: "leaf")
            } else {
                let columns = dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.adaptive(minimum: 150), spacing: 8.5)]
                    : Array(repeating: GridItem(.flexible(), spacing: 8.5), count: 3)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(stories) { story in
                        NavigationLink(value: CampusDestination.summary(story.id.uuidString)) {
                            MYWorkshopCardArtwork(card: card(for: story, profile: profile), remote: remote)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(story.cucumberName) 이야기 보기")
                        .accessibilityIdentifier("my.public.story.\(story.id.uuidString)")
                    }
                }
            }
        case .connected:
            ContentUnavailableView("공개 이야기에서 연결을 확인할 수 있어요", systemImage: "link",
                description: Text("나의 기부에서 이야기를 열어 이어진 이야기를 확인해 보세요."))
        case .collected:
            ContentUnavailableView("수집한 카드는 본인만 볼 수 있어요", systemImage: "rectangle.portrait.on.rectangle.portrait")
        }
    }

    private func card(for story: OiLiveStory, profile: OiProfile) -> MYCard {
        let region = remote.regions.first { $0.id == story.regionId }
        let school = remote.schools.first { $0.id == region?.schoolId }
        return MYCard(id: story.id.uuidString, title: story.cucumberName, image: story.cucumberAsset,
            school: MYSchool(id: school?.id ?? "", name: school?.name ?? "학교 정보 확인 중"), order: 0,
            body: story.body, donor: profile.publicDonorLine, date: story.createdDateLabel,
            storyID: story.id.uuidString, appearance: story.cardAsset,
            cucumberPortraitPath: story.cucumberArtwork?.path(.portrait), cardArtworkPath: story.cardArtworkPath)
    }

    private func load() async {
        let context = remote.continuationPrivacyKey
        let attempt = UUID()
        loadID = attempt
        do {
            let result = try await remote.publicAuthor(authorID)
            try Task.checkCancellation()
            guard loadID == attempt, context == remote.continuationPrivacyKey else { return }
            let authorStories = result.stories.enumerated().map { index, item in
                remote.campusStory(item, order: store.story(item.id.uuidString)?.order ?? store.stories.count + index,
                                   authorProfile: result.profile)
            }
            store.synchronize(stories: store.stories.filter { $0.authorID != authorID } + authorStories,
                              collected: store.collected)
            state = .loaded(result.profile, result.stories)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, loadID == attempt, context == remote.continuationPrivacyKey else { return }
            if case OiServiceError.unavailable = error { state = .unavailable }
            else { state = .failed }
        }
    }
}
