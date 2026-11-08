import SwiftUI

struct CampusExampleBadge: View {
    var body: some View {
        Label("디자인 예시", systemImage: "leaf")
            .font(CampusStyle.body(12)).foregroundStyle(CampusStyle.sectionGreen)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(CampusStyle.secondaryAction, in: Capsule())
    }
}

struct CampusStoryCardArtwork: View {
    let story: CampusStory
    @Environment(\.campusCucumberPortraitLoader) private var loadPortrait
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?
    @State private var legacyDraft: (owner: UUID, value: OiLocalDraft)?

    private var legacyOwner: UUID? {
        guard story.cardArtworkPath == nil, let remote, !remote.needsReauthentication,
              let owner = remote.account?.id, owner == story.authorID else { return nil }
        return owner
    }

    var body: some View {
        Group {
            if let image = story.example?.cardImage {
                Image(image).resizable().scaledToFit()
                    .accessibilityLabel("\(story.title) 예시 카드")
            } else if let path = story.cardArtworkPath {
                OiCucumberPortraitImage(path: path, label: "\(story.title) 카드") { path in
                    guard let loadPortrait else { throw OiServiceError.unavailable }
                    return try await loadPortrait(path)
                }
                    .aspectRatio(362 / 502, contentMode: .fit)
            } else if let legacyDraft, legacyDraft.owner == legacyOwner,
                      legacyDraft.value.id == UUID(uuidString: story.id),
                      let customization = legacyDraft.value.customization {
                OiDraftCardPreview(draft: legacyDraft.value.draft, customization: customization,
                    donorName: remote?.profile?.publicName ?? "")
            } else {
                OiStoryCardArtwork(name: story.title, introduction: story.excerpt, donor: story.donor,
                    date: story.date, tags: story.tags, assetName: story.image, portraitPath: story.cucumberPortraitPath,
                    loadPortrait: loadPortrait)
            }
        }
        .task(id: legacyOwner.map { "\($0)/\(story.id)" }) {
            legacyDraft = nil
            guard let remote, let owner = legacyOwner, let id = UUID(uuidString: story.id),
                  let record = try? await remote.localDraft(id: id, owner: owner),
                  !Task.isCancelled else { return }
            legacyDraft = (owner, record)
        }
    }
}
