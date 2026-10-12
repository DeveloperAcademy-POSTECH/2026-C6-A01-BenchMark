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
    init(repository: any ParticipationRepository) {
        _viewModel = State(initialValue: MyDonationsViewModel(repository: repository))
    }
    var body: some View {
        List {
            if viewModel.isLoading { ProgressView() }
            else if let error = viewModel.errorMessage {
                Text(error)
                Button("다시 시도") { Task { await viewModel.load() } }
            } else if viewModel.applications.isEmpty {
                ContentUnavailableView("아직 신청 내역이 없어요", systemImage: "heart",
                    description: Text("참여 신청과 학교에서 확인한 기부 내역을 이곳에서 안내드립니다."))
            } else {
                ForEach(viewModel.applications) { application in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(application.draft.message).font(.headline)
                        Text(application.applicationStatus.displayName)
                        Text(application.verificationStatus == .confirmedBySchool ? "학교 납입 확인 완료" : "학교 납입 확인 대기")
                        if let plaque = application.plaqueStatus { Text(plaque.displayName) }
                    }
                }
            }
        }
        .navigationTitle("내 기부").task { await viewModel.load() }
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
