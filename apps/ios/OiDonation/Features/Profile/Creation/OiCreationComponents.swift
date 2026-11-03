import SwiftUI

struct OiCreationProgressHeader: View {
    let step: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...4, id: \.self) { number in
                VStack(spacing: 3) {
                    if number.isMultiple(of: 2) { Text(label(number)).frame(height: 20) }
                    ZStack {
                        Image(number <= step ? "ConsentStepActive" : "ConsentStepInactiveRaised")
                            .resizable().scaledToFit().frame(height: 30)
                        Text("STEP \(number)").font(.custom("Paperlogy-7Bold", size: 10, relativeTo: .caption2))
                            .foregroundStyle(number <= step ? Color("OiLight") : Color("OiGreen").opacity(0.6))
                    }
                    if !number.isMultiple(of: 2) { Text(label(number)).frame(height: 20) }
                }.frame(maxWidth: .infinity)
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
        .foregroundStyle(Color("OiDark"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("4단계 중 \(step)단계, \(label(step))")
    }
    private func label(_ number: Int) -> String {
        guard number == step else { return "" }
        return ["약관 동의", "이야기 작성", "오이 커스텀", "카드 커스텀"][number - 1]
    }
}

struct OiCreationNextButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.custom("Paperlogy-5Medium", size: 17, relativeTo: .body))
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 20))
        .tint(Color("OiGreen")).disabled(!enabled)
    }
}

struct OiCreationSection<Content: View>: View {
    let title: String
    var hint: String = ""
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.custom("Paperlogy-6SemiBold", size: 26, relativeTo: .title2))
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(Color("OiGreen")) }
            }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OiStoryWritingStep: View {
    @Binding var draft: OiStoryDraft
    let grants: [OiWritingGrant]
    static let themes = ["가족", "우정", "사랑", "성장", "도전", "꿈", "배움", "경쟁", "협력", "갈등", "화해", "일탈", "나눔", "응원", "성취", "기타"]
    static let emotions = ["행복함", "즐거움", "뿌듯함", "고마움", "편안함", "설렘", "따뜻함", "짜릿함", "놀라움", "신남", "벅참", "그리움", "후련함", "부끄러움", "후회", "긴장감", "슬픔", "화남", "아쉬움", "기타"]
    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            OiCreationSection(title: "테마 선택", hint: "(택 1)") { tags(Self.themes, selected: $draft.theme) }
            OiCreationSection(title: "감정 선택", hint: "(택 1)") { tags(Self.emotions, selected: $draft.emotion) }
            OiCreationSection(title: "제목 입력", hint: "\(draft.title.count) / 100") {
                TextField("이야기 제목", text: $draft.title, axis: .vertical)
                    .accessibilityIdentifier("oi.draft.title").padding(20)
                    .background(Color("OiSoft"), in: RoundedRectangle(cornerRadius: 20))
            }
            OiCreationSection(title: "내용 입력", hint: "\(draft.body.count) / 10,000") {
                TextField("오래 남기고 싶은 이야기를 들려주세요", text: $draft.body, axis: .vertical)
                    .lineLimit(7...16).accessibilityIdentifier("oi.draft.body").padding(20)
                    .background(Color("OiSoft"), in: RoundedRectangle(cornerRadius: 20))
            }
            if grants.count > 1 {
                Picker("사용할 작성 승인", selection: $draft.grantId) {
                    Text("승인 선택").tag(Optional<UUID>.none)
                    ForEach(grants) { Text("승인 \($0.id.uuidString.prefix(8)) · 최대 \($0.storyLimit)개").tag(Optional($0.id)) }
                }.disabled(draft.revision > 0)
            }
        }.font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
    }
    private func tags(_ values: [String], selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(values, id: \.self) { value in
                    Button { selected.wrappedValue = value } label: {
                        Text(value).frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(selected.wrappedValue == value ? Color.white : Color("OiDark"))
                            .background(selected.wrappedValue == value ? Color("OiGreen") : Color("OiSoft"), in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.wrappedValue == value ? .isSelected : [])
                }
            }
            if !selected.wrappedValue.isEmpty && !values.contains(selected.wrappedValue) {
                Text("기존 선택: \(selected.wrappedValue)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
