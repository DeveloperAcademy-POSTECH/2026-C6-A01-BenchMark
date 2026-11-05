import SwiftUI

enum DonationCardSort: String, CaseIterable { case newest = "최신순", oldest = "오래된순", likes = "좋아요순" }

struct DonationDesignCard: Identifiable {
    let id: String
    let date: String
    let title: String
    let image: String
    let likes: Int
    let inProgress: Bool
    var longDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy.MM.dd.EEE"
        guard let value = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: value)
    }
    static let samples = [
        Self(id: "bench", date: "2026.10.09.FRI", title: "폭짜하던 10학번 전자공학과 친구들을 기억하며...", image: "DonationBench", likes: 53, inProgress: true),
        Self(id: "birthday", date: "2026.09.02.WED", title: "나의 생일을 축하해 준 5기 동기들을 기억하며...", image: "DonationBirthday", likes: 53, inProgress: false),
        Self(id: "campus", date: "2026.08.07.FRI", title: "아카데미에서 바라본 포스텍의 아름다운 풍경을 떠올리며...", image: "DonationCampus", likes: 21, inProgress: false),
        Self(id: "pond", date: "2026.06.29.MON", title: "지곡회관에서 먹은 학식과 창문으로 보인 호수가 생각나서...", image: "DonationPond", likes: 7, inProgress: false),
        Self(id: "sea", date: "2026.04.26.SUN", title: "동기들과 함께 놀러간 칠포 바다여행을 추억하며...", image: "DonationSea", likes: 12, inProgress: false)
    ]
}

private struct DonationPhotoFace: View {
    let card: DonationDesignCard
    let compact: Bool
    let flipped: Bool
    let onAdvance: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(card.image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                if card.id == "bench" && !compact && !flipped {
                    Image("DonationBenchObject").resizable().scaledToFit()
                        .frame(width: 132, height: 100)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.61)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.06),
                                        (card.id == "birthday" ? Color.orange : Color("OiGreen")).opacity(0.78)],
                               startPoint: .center, endPoint: .bottom)
                if flipped {
                    Color("OiGreen").opacity(0.95)
                    VStack(spacing: 20) {
                        Text("오래 남는 이야기").font(.headline)
                        Text(card.title).font(.custom("GriunOMIRI-Regular", size: 20)).multilineTextAlignment(.center)
                        if card.id == "bench" && !compact {
                            Text("10학번 동기들아 안녕 잘 지내니? 나 김사과야\n우리가 졸업한지도 벌써 10년이 지났네\n아직도 26학번 아가들이 우리의 폭짜를 이어가고 있더라구\n\n푸르고 아름다운 폭풍의 언덕에서 시원한 가을 바람을 맞으며 함께 짜장면을 먹을 때 너희들의 웃음소리가 잊히지 않는다\n\n다들 현업에서 열심히 일하느라 많이 바쁘겠지만 이 때의 기억을 떠올리면서 잠시나마 너희들이 따뜻함을 느꼈으면 좋겠어서 이 벤치를 남기게 되었어\n\n우리 앞으로 10년 20년 후에 계속 생길 우리 후배들을 생각하면서 더더 열심히 일하고 성장하자!\n많이 그립고 사랑한다 동기들아")
                                .font(.custom("GriunOMIRI-Regular", size: compact ? 10 : 14))
                                .lineSpacing(4)
                        }
                        Text(card.inProgress ? "명패 진행 화면 예시" : "추억을 담은 기부 이야기 예시").font(.caption)
                    }.padding(24).foregroundStyle(.white)
                }
                VStack(alignment: .leading) {
                    HStack {
                        if card.inProgress {
                            Text("진행중").font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color("OiGreen").opacity(0.85), in: Capsule())
                        }
                        Spacer()
                        Button(action: onAdvance) {
                            HStack(spacing: 4) {
                                if !compact { Text(flipped ? "돌아가기" : "뒤집기").font(.caption) }
                                Image(systemName: "arrow.uturn.right").font(.system(size: 10))
                            }.foregroundStyle(.black).padding(8).background(Color("OiSoft"), in: Capsule())
                        }.accessibilityLabel(flipped ? "이야기 카드 앞면 보기" : "이야기 카드 뒤집기")
                    }
                    Spacer()
                    if !flipped {
                        Text(compact ? card.date : card.longDate).font(.custom("GriunOMIRI-Regular", size: compact ? 12 : 22))
                        Text(card.title).font(.custom("GriunOMIRI-Regular", size: compact ? 15 : 17)).lineLimit(compact ? 3 : 1)
                        if !compact {
                            Divider().overlay(.white.opacity(0.6))
                            HStack {
                                Label("좋아요  \(card.likes)", systemImage: "heart")
                                Spacer()
                                Label("공감해요  21", systemImage: "hand.thumbsup")
                                Spacer()
                                Label("응원해요  7", systemImage: "star")
                            }.font(.system(size: 11))
                        }
                    }
                }.padding(compact ? 16 : 24).foregroundStyle(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .shadow(color: Color("OiGreen").opacity(0.25), radius: 6, y: 3)
        }.frame(height: compact ? 240 : 502)
    }
}


struct DonationStoryCard: View {
    let card: DonationDesignCard
    let compact: Bool
    @State private var page = 0

    var body: some View {
        if compact {
            DonationPhotoFace(card: card, compact: true, flipped: page == 1) { page = page == 0 ? 1 : 0 }
        } else {
            ZStack {
                if page == 0 {
                DonationPhotoFace(card: card, compact: false, flipped: false) {
                    withAnimation { page = 1 }
                }
                } else if page == 1 {
                DonationPhotoFace(card: card, compact: false, flipped: true) {
                    withAnimation { page = 0 }
                }
                } else { locationFace }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .frame(height: 502)
            .background(DonationCardSwipeHandler { direction in
                withAnimation(.easeInOut(duration: 0.25)) {
                    page = min(2, max(0, page + direction))
                }
            })
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Button { withAnimation { page = index } } label: {
                            Circle().fill(index == page ? Color.white : Color.white.opacity(0.45))
                                .frame(width: 6, height: 6).padding(5)
                        }.accessibilityLabel(["사진 면 보기", "이야기 면 보기", "위치 지도 보기"][index])
                            .accessibilityAddTraits(index == page ? .isSelected : [])
                    }
                }.padding(.bottom, 4)
            }
            .accessibilityValue(["사진", "이야기", "위치 지도"][page])
        }
    }

    private var locationFace: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image("DonationLocationMap").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .opacity(0.65)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("위치 예시").font(.caption).padding(8)
                            .background(Color("OiGreen").opacity(0.7), in: Capsule())
                        Spacer()
                        Button { withAnimation { page = 0 } } label: {
                            Label("닫기", systemImage: "xmark").font(.caption)
                                .padding(8).background(Color("OiSoft"), in: Capsule())
                        }.accessibilityLabel("카드 사진으로 돌아가기")
                    }
                    HStack(spacing: 0) {
                        locationBadge("구역", value: "A")
                        locationBadge("번호", value: "3")
                    }
                    Spacer()
                    Text("Figma의 예시 위치입니다. 실제 기부 벤치 위치가 아닙니다.")
                        .font(.caption).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }.padding(20)
            }.background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 30))
        }.frame(height: 502)
    }

    private func locationBadge(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption)
            Text(value).font(.system(size: 30, weight: .semibold))
        }.foregroundStyle(.white).frame(width: 67, height: 64)
            .background(Color("OiYellowGreen"), in: RoundedRectangle(cornerRadius: 10))
    }
}


/// Recognize horizontal intent before beginning, leaving vertical scrolling untouched.
private struct DonationCardSwipeHandler: UIViewRepresentable {
    let onSwipe: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSwipe: onSwipe) }
    func makeUIView(context: Context) -> UIView {
        let view = GestureMarker()
        view.isUserInteractionEnabled = false
        context.coordinator.marker = view
        view.onWindowChanged = { [weak coordinator = context.coordinator] in coordinator?.attach() }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.onSwipe = onSwipe }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }

    final class GestureMarker: UIView {
        var onWindowChanged: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); onWindowChanged?() }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var marker: UIView?
        weak var host: UIView?
        var onSwipe: (Int) -> Void
        lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
        init(onSwipe: @escaping (Int) -> Void) { self.onSwipe = onSwipe }
        func attach() {
            detach()
            guard let host = marker?.window else { return }
            self.host = host
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            host.addGestureRecognizer(pan)
        }
        func detach() { host?.removeGestureRecognizer(pan) }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let marker, marker.bounds.contains(pan.location(in: marker)) else { return false }
            let velocity = pan.velocity(in: marker)
            return abs(velocity.x) > abs(velocity.y) * 1.3
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc private func moved(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let delta = gesture.translation(in: marker)
            guard abs(delta.x) > 45 else { return }
            onSwipe(delta.x < 0 ? 1 : -1)
        }
    }
}
