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
    var body: some View {
        if let image = story.example?.cardImage {
            Image(image).resizable().scaledToFit()
                .accessibilityLabel("\(story.title) 예시 카드")
        } else {
            MYCardArtwork(card: MYCard(id: story.id, title: story.title, image: story.image,
                school: .postech, order: story.order, body: story.body, donor: story.donor, date: story.date))
        }
    }
}
