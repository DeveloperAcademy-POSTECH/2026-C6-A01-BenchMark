import SwiftUI

enum CampusStyle {
    static let green = Color(red: 0.44, green: 0.55, blue: 0.25)
    static let lightGreen = Color(red: 0.60, green: 0.73, blue: 0.39)
    static let coral = Color(red: 0.784, green: 0.376, blue: 0.365)
    static let gold = Color(red: 0.831, green: 0.714, blue: 0.345)
    static let action = LinearGradient(colors: [coral, gold], startPoint: .leading, endPoint: .trailing)
    static func heading(_ size: CGFloat) -> Font { .custom("Paperlogy-9Black", size: size, relativeTo: .title) }
    static func body(_ size: CGFloat) -> Font { .custom("Paperlogy-4Regular", size: size, relativeTo: .body) }
    static func hand(_ size: CGFloat) -> Font { .custom("GriunOMIRI-Regular", size: size, relativeTo: .body) }
    static func background(_ palette: Int) -> Color {
        [Color(red: 1, green: 0.965, blue: 0.918), Color(red: 0.949, green: 0.953, blue: 1), Color(red: 0.996, green: 0.941, blue: 0.941)][palette % 3]
    }
    static func portrait(_ palette: Int) -> LinearGradient {
        let colors: [[Color]] = [[Color(red: 0.98, green: 0.85, blue: 0.79), Color(red: 1, green: 0.90, blue: 0.64)], [.init(red: 0.73, green: 0.80, blue: 1), .init(red: 0.63, green: 0.90, blue: 1)], [.init(red: 1, green: 0.57, blue: 0.41), .init(red: 1, green: 0.89, blue: 0.63)]]
        return LinearGradient(colors: colors[palette % 3], startPoint: .top, endPoint: .bottom)
    }
}

struct CampusDonorBadge: View {
    let size: CGFloat
    var body: some View {
        Image("OiVerified").resizable().scaledToFit().frame(width: size, height: size)
            .overlay { Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .black)).foregroundStyle(.white) }
            .accessibilityHidden(true)
    }
}

struct CampusTags: View {
    let story: CampusStory
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(story.tags, id: \.self) { tag in
                Text(tag).font(.custom("Mona12TextKR-Regular", size: compact ? 10 : 13, relativeTo: .caption))
                    .foregroundStyle(Color(red: 0.41, green: 0.19, blue: 0.19))
                    .padding(.horizontal, compact ? 10 : 12).padding(.vertical, compact ? 5 : 7)
                    .background(CampusStyle.coral.opacity(0.14), in: Capsule())
            }
        }
    }
}

struct CampusStoryRow: View {
    let story: CampusStory
    var body: some View {
        HStack(spacing: 12) {
            Image(story.image).resizable().scaledToFit().frame(width: 78, height: 93)
                .background(CampusStyle.portrait(story.palette), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) {
                    Text(story.title).font(CampusStyle.heading(20)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    CampusTags(story: story, compact: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(story.donor)
                    Text(story.location)
                    Text(story.date)
                }.font(CampusStyle.hand(12)).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(.black).padding(7).frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusStyle.background(story.palette), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct CampusCollectButton: View {
    let story: CampusStory
    let store: CampusStoryStore
    var body: some View {
        Button { store.collect(story) } label: {
            Label(store.collected.contains(story.id) ? "수집 완료" : "수집하기", systemImage: store.collected.contains(story.id) ? "checkmark" : "plus")
                .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white).background(CampusStyle.action, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).sensoryFeedback(.success, trigger: store.collected.contains(story.id))
        .accessibilityIdentifier("campus.collect")
    }
}
