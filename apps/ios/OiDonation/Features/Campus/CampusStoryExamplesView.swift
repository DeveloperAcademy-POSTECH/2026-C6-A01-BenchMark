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
    var body: some View {
        if let image = story.example?.cardImage {
            Image(image).resizable().scaledToFit()
                .accessibilityLabel("\(story.title) 예시 카드")
        } else {
            OiStoryCardArtwork(name: story.title, introduction: story.excerpt, donor: story.donor,
                date: story.date, tags: story.tags, assetName: story.image, portraitPath: story.cucumberPortraitPath,
                loadPortrait: loadPortrait)
        }
    }
}
