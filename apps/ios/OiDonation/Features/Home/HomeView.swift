import SwiftUI

struct HomeView: View {
    var onParticipation: (() -> Void)?
    @State private var viewModel: HomeViewModel
    @State private var selectedDestination: HomeDestination?

    init(repository: any HomeRepository, onParticipation: (() -> Void)? = nil) {
        self.onParticipation = onParticipation
        _viewModel = State(initialValue: HomeViewModel(repository: repository))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    header
                    HomeStoryBanner(height: max(160, min(219, geometry.size.height - 520))) {
                        selectedDestination = .introduction
                    }
                    donationCard
                    shortcuts
                    switch viewModel.state {
                    case .idle, .loading:
                        ProgressView("현황을 불러오는 중입니다").frame(height: 180)
                    case .loaded(let dashboard):
                        HomeImpactCard(dashboard: dashboard)
                        if dashboard.isExample {
                            Text("참여 현황과 이름은 디자인 확인용 예시입니다.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    case .unavailable:
                        VStack(spacing: 12) {
                            Text("참여 현황을 준비 중이에요").font(.headline)
                            Text("학교에서 확인한 현황이 준비되면 안내드릴게요.").font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("다시 확인") { Task { await viewModel.load() } }
                        }.frame(maxWidth: .infinity).frame(height: 180)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }.clipped()
        }
        .background(Color.white)
        .task { await viewModel.load() }
        .sheet(item: $selectedDestination) { HomeInformationSheet(destination: $0) }
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
                    (Text(viewModel.donorName).fontWeight(.semibold) + Text(" 님의 기부 내역"))
                        .font(.system(size: 20)).foregroundStyle(Color("OiOlive"))
                        .minimumScaleFactor(0.75).lineLimit(1)
                }
                Text("아직 기부 내역이 없어요\n기부자님의 이야기를 남겨보시겠어요?")
                    .font(.system(size: 13)).lineSpacing(3).foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                if let onParticipation { onParticipation() } else { selectedDestination = .donation }
            } label: {
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

#Preview {
    HomeView(repository: DesignDemoHomeRepository())
}
