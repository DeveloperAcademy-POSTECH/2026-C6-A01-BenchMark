import SwiftUI

/// Replace the design fixture with school-confirmed data when the service is connected.
struct HomeDashboard {
    var donorName: String
    var attachedBenchCount: Int
    var targetBenchCount: Int
    var participantCount: Int
    var progress: Int
    var isExample: Bool

    static let designExample = HomeDashboard(
        donorName: "김사과", attachedBenchCount: 17, targetBenchCount: 30,
        participantCount: 235, progress: 78, isExample: true
    )
}

struct HomeView: View {
    var onARTap: (() -> Void)? = nil
    var dashboard: HomeDashboard = .designExample
    @State private var selectedDestination: HomeDestination?
    @State private var selectedTab = 0
    @State private var isARPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 1: tabDestination(.myDonations)
                case 2: tabDestination(.donation)
                case 3: tabDestination(.map)
                default: homeContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            bottomBar
                .background(Color.white)
        }
        .background(Color.white)
        .tint(Color("OiGreen"))
        .fullScreenCover(isPresented: $isARPresented) { ARView() }
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                tabButton("홈", title: "홈", symbol: "house.fill", index: 0)
                tabButton("내 기부", title: "내 기부", symbol: "heart.fill", index: 1)
                tabButton("후원", title: "후원", symbol: "hand.palm.facing.fill", index: 2)
                tabButton("벤치지도", title: "벤치지도", symbol: "map.fill", index: 3)
            }
            .padding(4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))

            Button {
                if let onARTap { onARTap() } else { isARPresented = true }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 62, height: 62)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
            }
            .accessibilityLabel("AR 카메라 열기")
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func tabButton(_ label: String, title: String, symbol: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 23, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(selectedTab == index ? Color("OiGreen") : Color.primary)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background {
                if selectedTab == index { Capsule().fill(Color("OiSoft")) }
            }
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }

    private func tabDestination(_ destination: HomeDestination) -> some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(destination.message).multilineTextAlignment(.center)
                if destination == .donation {
                    Link("POSTECH 공식 기부 사이트", destination: URL(string: "https://vision.postech.ac.kr/web/?top=participation&sub=contract")!)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24).navigationTitle(destination.title)
        }
    }

    private var homeContent: some View {
        GeometryReader { geometry in
            ScrollView {
            VStack(spacing: 12) {
                header
                HomeStoryBanner(height: max(160, min(219, geometry.size.height - 520))) {
                    selectedDestination = .introduction
                }
                donationCard
                shortcuts
                HomeImpactCard(dashboard: dashboard)
                if dashboard.isExample {
                    Text("참여 현황과 이름은 디자인 확인용 예시입니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            }
            .clipped()
        }
        .background(Color.white)
        .sheet(item: $selectedDestination) { destination in
            HomeInformationSheet(destination: destination)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("OiLogo").resizable().scaledToFit().frame(width: 38, height: 34)
            Image("OiWordmark").resizable().scaledToFit().frame(width: 101, height: 24)
            Spacer()
            headerButton("bell.fill", label: "알림", destination: .notifications)
            headerButton("person.fill", label: "내 프로필", destination: .profile)
        }
        .frame(height: 40)
    }

    private func headerButton(_ symbol: String, label: String, destination: HomeDestination) -> some View {
        Button { selectedDestination = destination } label: {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color("OiDark"))
                .frame(width: 44, height: 44)
                .background { Image("HomeProfileBackground").resizable().frame(width: 38, height: 38) }
        }
        .accessibilityLabel(label)
    }

    private var donationCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 5) {
                    Image("OiLogo").resizable().scaledToFit().frame(width: 21, height: 18)
                    (Text(dashboard.donorName).fontWeight(.semibold) + Text(" 님의 기부 내역"))
                        .font(.system(size: 20)).foregroundStyle(Color("OiOlive"))
                        .minimumScaleFactor(0.75).lineLimit(1)
                }
                Text("아직 기부 내역이 없어요\n기부자님의 이야기를 남겨보시겠어요?")
                    .font(.system(size: 13)).lineSpacing(3).foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { selectedDestination = .donation } label: {
                Text("기부\n시작").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("OiGreen"))
                    .multilineTextAlignment(.center).frame(width: 70, height: 70)
                    .background { Image("HomeDonationButton").resizable().frame(width: 90, height: 86) }
            }
            .accessibilityLabel("기부 시작")
        }
        .padding(.horizontal, 21).padding(.vertical, 21)
        .frame(minHeight: 116)
        .background(Color("OiLight"), in: RoundedRectangle(cornerRadius: 20))
    }

    private var shortcuts: some View {
        HStack(spacing: 15) {
            shortcut("receipt.fill", title: "기부금영수증", destination: .receipt)
            shortcut("gift.fill", title: "이벤트/혜택", destination: .benefits)
            shortcut("megaphone.fill", title: "오이 소식", destination: .news)
            shortcut("heart.square.fill", title: "정기후원", destination: .recurring)
        }
    }

    private func shortcut(_ symbol: String, title: String, destination: HomeDestination) -> some View {
        Button { selectedDestination = destination } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 23))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color("OiOlive"))
            .frame(maxWidth: .infinity).frame(height: 79)
            .background(Color("OiShortcut"), in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color("OiDark").opacity(0.25), radius: 2, x: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeStoryBanner: View {
    var height: CGFloat = 219
    let onDetails: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Figma crops the portrait image 279 points above the 219-point banner.
                Image("HomeBench").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.width * 1096 / 729)
                    .offset(y: -279 * geometry.size.width / 362)
                    .frame(width: geometry.size.width, height: height, alignment: .top)
                    .clipped()
                LinearGradient(colors: [Color(red: 47/255, green: 63/255, blue: 24/255).opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    Text("“오래도록 남는 이야기, 오이기부”")
                        .font(.system(size: 22, weight: .medium)).minimumScaleFactor(0.7).lineLimit(1)
                    Text("학교의 내일에 보탠 마음, 캠퍼스에 이야기로 남아요.\n첫 기부로 기억하고 싶은 순간을 벤치에 남겨보세요.")
                        .font(.system(size: 12)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: onDetails) {
                        HStack(spacing: 5) {
                            Text("자세히보기").font(.system(size: 12, weight: .light))
                            Image(systemName: "arrow.right").font(.system(size: 10))
                        }
                        .foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color("OiLight"), in: Capsule())
                    }
                }
                .foregroundStyle(Color("OiSoft")).padding(24).padding(.top, 7)
                .frame(height: height)
            }
            .frame(width: geometry.size.width, height: height).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .frame(height: height)
    }
}

private struct HomeImpactCard: View {
    let dashboard: HomeDashboard
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 9) {
                Text("POSTECH 오이").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color("OiDark"))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color("OiYellowGreen"), in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomTrailingRadius: 20))
                ZStack(alignment: .topTrailing) {
                    Image("OiCucumber").resizable().scaledToFit().frame(width: 115, height: 125)
                        .opacity(0.3)
                        .overlay(alignment: .bottom) {
                            Image("OiCucumber").resizable().scaledToFit().frame(width: 115, height: 125)
                                .mask(VStack(spacing: 0) { Color.clear.frame(height: 52); Color.black })
                        }
                    Text("\(dashboard.progress)%").font(.system(size: 29, weight: .medium)).italic()
                        .foregroundStyle(Color("OiGreen")).offset(x: 30, y: 13)
                }
                .padding(.leading, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("설치된 벤치 수").font(.system(size: 12, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(dashboard.attachedBenchCount)").font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color("OiGreen"))
                    Image("HomeSlash").resizable().scaledToFit().frame(width: 20, height: 29).accessibilityHidden(true)
                    Text("\(dashboard.targetBenchCount)").font(.system(size: 28)).foregroundStyle(Color("OiGreen").opacity(0.5))
                }
                .frame(maxWidth: .infinity).frame(height: 40)
                Image("HomeDivider").resizable().frame(height: 0.4).accessibilityHidden(true)
                Text("누적 참여자 수").font(.system(size: 12, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(dashboard.participantCount)").font(.system(size: 47, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color("OiGreen"))
                    Text("명").font(.system(size: 28)).foregroundStyle(Color("OiGreen").opacity(0.5))
                }
                .frame(maxWidth: .infinity).frame(height: 40)
            }
            .foregroundStyle(Color("OiDark"))
            .padding(14).frame(maxWidth: .infinity).frame(height: 162)
            .background(Color("OiSoft"), in: RoundedRectangle(cornerRadius: 20))
            .padding(.vertical, 8).padding(.trailing, 10)
        }
        .frame(height: 180)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color("OiYellowGreen"), lineWidth: 2))
    }
}

enum HomeDestination: String, Identifiable {
    case introduction, donation, receipt, benefits, news, recurring, notifications, profile, myDonations, map
    var id: String { rawValue }
    var title: String {
        switch self {
        case .introduction: "오이기부 소개"
        case .donation: "기부 시작"
        case .receipt: "기부금영수증"
        case .benefits: "이벤트/혜택"
        case .news: "오이 소식"
        case .recurring: "정기후원"
        case .notifications: "알림"
        case .profile: "내 프로필"
        case .myDonations: "내 기부"
        case .map: "벤치지도"
        }
    }
    var message: String {
        switch self {
        case .introduction: "오래 남는 이야기 기부. 후배를 응원하거나 기억하고 싶은 순간을 POSTECH의 기존 벤치에 남겨보세요."
        case .donation, .recurring: "기부는 POSTECH의 공식 절차로 진행합니다. 명패 제공 기준과 벤치 배정은 학교와 협의 후 안내드립니다."
        case .receipt: "기부금영수증은 POSTECH에서 발급합니다. 공식 발전기금 사이트에서 확인하거나 학교에 문의해 주세요."
        case .benefits: "새로운 이벤트와 기부자 혜택이 준비되면 안내드릴게요."
        case .news: "새로운 오이기부 소식이 준비되면 이곳에서 전해드릴게요."
        case .notifications: "아직 새로운 알림이 없어요."
        case .profile: "로그인 후 나의 정보와 이야기를 관리할 수 있어요."
        case .myDonations: "아직 확인된 기부 내역이 없어요. 학교에서 납입을 확인한 이후 진행 상황을 안내드립니다."
        case .map: "참여 가능한 벤치는 학교 확인 후 안내드릴게요."
        }
    }
}

struct HomeInformationSheet: View {
    let destination: HomeDestination
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(destination.message).font(.body)
                if [.donation, .recurring, .receipt].contains(destination) {
                    Link("POSTECH 공식 기부 사이트", destination: URL(string: "https://vision.postech.ac.kr/web/?top=participation&sub=contract")!)
                        .buttonStyle(.borderedProminent).tint(Color("OiGreen"))
                }
                Spacer()
            }
            .padding(24).navigationTitle(destination.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

#Preview {
    HomeView()
}
