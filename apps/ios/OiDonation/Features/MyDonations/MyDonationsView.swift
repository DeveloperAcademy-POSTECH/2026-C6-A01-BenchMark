import SwiftUI

@MainActor @Observable
final class MyDonationsViewModel {
    private(set) var applications: [ParticipationApplication] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let repository: any ParticipationRepository
    init(repository: any ParticipationRepository) { self.repository = repository }
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { applications = try await repository.fetchApplications() }
        catch is CancellationError { }
        catch { errorMessage = "신청 내역을 불러오지 못했어요." }
    }
}

struct MyDonationsView: View {
    @State private var viewModel: MyDonationsViewModel
    @State private var sort: DonationCardSort = .newest
    @State private var grid = false
    let showDesignExamples: Bool
    var onParticipation: () -> Void

    init(repository: any ParticipationRepository, showDesignExamples: Bool = false,
         onParticipation: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: MyDonationsViewModel(repository: repository))
        self.showDesignExamples = showDesignExamples
        self.onParticipation = onParticipation
    }

    private var examples: [DonationDesignCard] {
        DonationDesignCard.samples.sorted {
            switch sort {
            case .newest: $0.date > $1.date
            case .oldest: $0.date < $1.date
            case .likes: $0.likes == $1.likes ? $0.date > $1.date : $0.likes > $1.likes
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if showDesignExamples {
                    HStack(spacing: 8) {
                        ForEach(DonationCardSort.allCases, id: \.self) { option in
                            Button { sort = option } label: {
                                Text(option.rawValue).font(.system(size: 16, weight: .medium))
                                    .padding(.horizontal, 15).padding(.vertical, 8)
                                    .foregroundStyle(sort == option ? Color.white : Color("OiGreen"))
                                    .background(sort == option ? Color("OiYellowGreen") : Color("OiSoft"), in: Capsule())
                            }.accessibilityAddTraits(sort == option ? .isSelected : [])
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            layoutButton(false, symbol: "square.fill")
                            layoutButton(true, symbol: "square.grid.2x2.fill")
                        }.padding(2).background(Color("OiSoft"), in: Capsule())
                    }
                    if grid {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(examples) { DonationStoryCard(card: $0, compact: true) }
                            Button(action: onParticipation) {
                                Text("다음 시즌\n기부하기").font(.title3.bold())
                                    .frame(maxWidth: .infinity).frame(height: 240)
                                    .background(Color("OiSoft"), in: RoundedRectangle(cornerRadius: 30))
                            }
                        }
                    } else {
                        ForEach(examples.prefix(2)) { DonationStoryCard(card: $0, compact: false) }
                        Button("다음 시즌 기부하기", action: onParticipation)
                            .font(.headline).foregroundStyle(.white).padding(.horizontal, 32).padding(.vertical, 14)
                            .background(Color("OiGreen"), in: Capsule())
                    }
                    Text("디자인 확인용 예시입니다. 실제 기부 내역이나 사용자 반응이 아닙니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if viewModel.isLoading { ProgressView() }
                else if let error = viewModel.errorMessage, !showDesignExamples {
                    Text(error)
                    Button("다시 시도") { Task { await viewModel.load() } }
                } else if viewModel.applications.isEmpty && !showDesignExamples {
                    ContentUnavailableView("아직 신청 내역이 없어요", systemImage: "heart",
                        description: Text("참여 신청과 학교에서 확인한 기부 내역을 이곳에서 안내드립니다."))
                    Button("이야기 남기기", action: onParticipation)
                } else {
                    ForEach(viewModel.applications) { application in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(application.draft.message).font(.headline)
                            Text(application.applicationStatus.displayName)
                            Text(application.verificationStatus == .confirmedBySchool ? "학교 납입 확인 완료" : "학교 납입 확인 대기")
                            if let plaque = application.plaqueStatus { Text(plaque.displayName) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .background(.white).toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    private func layoutButton(_ value: Bool, symbol: String) -> some View {
        Button { grid = value } label: {
            Image(systemName: symbol).font(.system(size: 13))
                .frame(width: 32, height: 29)
                .background(grid == value ? Color.white : .clear, in: Capsule())
        }.accessibilityLabel(value ? "격자 보기" : "목록 보기")
            .accessibilityAddTraits(grid == value ? .isSelected : [])
    }
}

extension ApplicationStatus {
    var displayName: String {
        switch self {
        case .draft: "초안"; case .submitted: "신청 접수"; case .underReview: "검토 중"
        case .approved: "신청 승인"; case .revisionRequested: "수정 요청"; case .cancelled: "신청 취소"
        }
    }
}
extension PlaqueStatus {
    var displayName: String {
        switch self { case .awaitingProduction: "제작 대기"; case .inProduction: "제작 중"; case .attached: "부착 완료" }
    }
}
