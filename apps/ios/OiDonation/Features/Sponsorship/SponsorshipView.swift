import SwiftUI

struct SponsorshipView: View {
    let benches: any BenchRepository
    let participation: any ParticipationRepository
    var onHome: () -> Void

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 6) {
                    Color.clear.frame(height: 135)
                    ForEach(1...5, id: \.self) { step in
                        Text("\(step)").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color("OiSoft")).frame(width: 26, height: 26)
                            .background(Color("OiGreen"), in: Circle())
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 26)
                .background { RoundedRectangle(cornerRadius: 3).fill(Color("OiSoft")).frame(width: 6) }
                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink {
                        PlaquePreviewExperienceView()
                    } label: {
                        Label("명패 미리보기", systemImage: "rectangle.and.pencil.and.ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color("OiSoft"), in: RoundedRectangle(cornerRadius: 16))
                    }.accessibilityIdentifier("sponsorship.plaquePreview")
                        .padding(.bottom, 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("누군가의 기억이")
                        Text("다른 누군가의")
                        Text("쉼이 될 수 있도록.").foregroundStyle(Color("OiYellowGreen"))
                    }.font(.custom("GriunOMIRI-Regular", size: 30)).lineSpacing(8)
                    Text("기억이 남는 장소에는 늘 사람이 있습니다.\n잠시 앉아 나눈 대화, 함께보낸 오후...\n그리고 오래 남은 마음.\n\n벤치마크는 그 마음을 기부와 연결하고,\n함께 머무를 수 있는 공간으로 이어가는 방법을 찾습니다.")
                        .font(.custom("GriunOMIRI-Regular", size: 14)).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 54).padding(.bottom, 38)
                    Text("우리가 이어가려는 것").font(.custom("GriunOMIRI-Regular", size: 20)).padding(.bottom, 14)
                    valueSection("01  _  MEMORY", title: "장소를 기억하는\n사람들의 마음",
                        detail: "마음이 머물렀던 장소에서 출발합니다.\n어떤 장소가 나에게 소중한지 묻는 것에서 시작합니다.\n공간의 의미는 그곳에 머물렀던 사람에게서 옵니다.")
                    valueSection("02  _  CONNECTION", title: "마음을 전하는\n구체적인 방법",
                        detail: "기부와 공간을 잇는 참여 방식을 고민합니다.\n좋은 뜻이 실제 공간과 연결되도록,\n참여하는 사람과 공간을 운영하는 사람 사이의 과정을 고민합니다", trailing: true)
                    valueSection("03  _  CONTINUITY", title: "만드는 순간부터\n그다음의 시간까지",
                        detail: "다음 사람이 누를 쉼과 그 이후를 생각합니다\n공간이 만들어진 뒤에도 의미가 이어질 수 있도록,\n진행 과정과 이후의 돌봄까지 함께 생각합니다.")
                    NavigationLink {
                        ParticipationView(benches: benches, participation: participation)
                    } label: {
                        Text("기부 시작하기").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color("OiSoft"))
                            .frame(maxWidth: .infinity).frame(height: 57)
                            .background(Color("OiGreen"), in: RoundedRectangle(cornerRadius: 20))
                    }.padding(.top, 16)
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button(action: onHome) {
                    Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                        .frame(width: 50, height: 50).background(.ultraThinMaterial, in: Circle())
                }.accessibilityLabel("홈으로 돌아가기")
                Spacer()
                HStack(spacing: 6) {
                    Image("OiLogo").resizable().scaledToFit().frame(width: 38, height: 34)
                    Image("OiWordmark").resizable().scaledToFit().frame(width: 101, height: 24)
                }
                Spacer()
                Color.clear.frame(width: 50, height: 50)
            }.padding(.horizontal, 20).padding(.vertical, 12).background(.white)
        }
        .background(.white).foregroundStyle(.black).toolbar(.hidden, for: .navigationBar)
    }

    private func valueSection(_ number: String, title: String, detail: String, trailing: Bool = false) -> some View {
        HStack(spacing: 20) {
            if !trailing { Rectangle().fill(Color("OiGreen").opacity(0.6)).frame(width: 0.5) }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 14) {
                Text(number).font(.system(size: 10, weight: .light))
                Text(title).font(.custom("GriunOMIRI-Regular", size: 20)).lineSpacing(6)
                Text(detail).font(.system(size: 8, weight: .light)).lineSpacing(3)
            }.multilineTextAlignment(trailing ? .trailing : .leading).frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
            if trailing { Rectangle().fill(Color("OiGreen").opacity(0.6)).frame(width: 0.5) }
        }.frame(minHeight: 133).padding(.vertical, 2)
    }
}
