import SwiftUI

enum CampusStyle {
    static let sectionGreen = Color(red: 84 / 255, green: 105 / 255, blue: 48 / 255)
    static let secondaryAction = Color(red: 211 / 255, green: 219 / 255, blue: 196 / 255)
    static let summaryAction = Color(red: 90 / 255, green: 112 / 255, blue: 51 / 255)
    static let listBackground = Color(white: 0.96)
    static let mapSheet = Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255)
    static let mapAction = Color(red: 101 / 255, green: 126 / 255, blue: 58 / 255)
    static func medium(_ size: CGFloat) -> Font { .custom("Paperlogy-5Medium", size: size, relativeTo: .body) }
    static func semibold(_ size: CGFloat) -> Font { .custom("Paperlogy-6SemiBold", size: size, relativeTo: .headline) }
    static let green = Color(red: 0.44, green: 0.55, blue: 0.25)
    static let lightGreen = Color(red: 0.60, green: 0.73, blue: 0.39)
    static let coral = Color(red: 0.784, green: 0.376, blue: 0.365)
    static let gold = Color(red: 0.831, green: 0.714, blue: 0.345)
    static let action = LinearGradient(colors: [coral, gold], startPoint: .leading, endPoint: .trailing)
    static func characterTitle(_ size: CGFloat) -> Font { .custom("PearToucan-Bold", size: size, relativeTo: .headline) }
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
    var size: CGFloat? = nil
    private var color: Color {
        [Color(white: 0.60), Color(red: 21 / 255, green: 117 / 255, blue: 167 / 255),
         Color(red: 231 / 255, green: 125 / 255, blue: 45 / 255)][story.palette % 3]
    }
    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(story.tags, id: \.self) { tag in
                Text("#" + tag.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
                    .font(CampusStyle.body(size ?? (compact ? 12 : 15)))
                    .tracking(compact ? 0.24 : 0.3).foregroundStyle(color)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
}

struct CampusStoryRow: View {
    let story: CampusStory
    var showsDate = true
    var outlined = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 12) {
                Image(story.portraitImage).resizable().scaledToFit().padding(4)
                    .frame(width: 86, height: 86)
                    .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        Text(story.title).font(CampusStyle.characterTitle(20)).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        CampusTags(story: story, compact: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("| " + story.donor)
                        Text("| " + story.location)
                    }.font(CampusStyle.body(14)).lineSpacing(7).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(.black).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(outlined ? CampusStyle.secondaryAction : .clear, lineWidth: 1))
            if showsDate {
                Text(story.date).font(CampusStyle.body(10)).foregroundStyle(Color(white: 152/255)).padding(.trailing, 20)
            }
        }.contentShape(Rectangle())
    }
}

struct CampusCollectButton: View {
    let story: CampusStory
    let store: CampusStoryStore
    var fill: Color = CampusStyle.green
    var body: some View {
        Button { store.collect(story) } label: {
            Text(story.isExample ? "예시 카드" : store.collected.contains(story.id) ? "수집 완료" : "수집하기")
                .font(CampusStyle.semibold(16)).frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white).background(fill, in: RoundedRectangle(cornerRadius: 20))
        }
        .disabled(story.isExample || store.isExample || store.collected.contains(story.id))
        .buttonStyle(.plain).sensoryFeedback(.success, trigger: store.collected.contains(story.id))
        .accessibilityIdentifier("campus.collect")
    }
}
