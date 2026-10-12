import SwiftUI

struct ParticipationView: View {
    @State private var viewModel: ParticipationViewModel
    init(benches: any BenchRepository, participation: any ParticipationRepository) {
        _viewModel = State(initialValue: ParticipationViewModel(benches: benches, participation: participation))
    }
    var body: some View {
        Form {
            if let application = viewModel.application {
                Section("참여 신청") {
                    Text("신청이 접수됐어요")
                    Text("명패 문구: \(application.draft.message)")
                    Text("기부 확인 대기").foregroundStyle(.secondary)
                    Text("신청 접수는 납입 완료가 아닙니다. 학교의 확인 후 다음 진행을 안내드립니다.")
                }
                officialGuidance
            } else {
                Section("이야기를 남길 벤치") {
                    if viewModel.isLoading { ProgressView() }
                    else if viewModel.benches.isEmpty {
                        Text("참여 가능한 벤치를 준비 중이에요.")
                        Button("다시 확인") { Task { await viewModel.load() } }
                    } else {
                        Picker("벤치", selection: $viewModel.draft.benchID) {
                            Text("선택해 주세요").tag("")
                            ForEach(viewModel.benches) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                Section("오래 남길 이야기") {
                    TextField("명패 문구", text: $viewModel.draft.message, axis: .vertical)
                    TextField("개인적인 이야기", text: $viewModel.draft.story, axis: .vertical).lineLimit(3...6)
                    Text("문구 길이와 명패 제공 기준은 학교와 협의 후 안내드립니다.").font(.caption)
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button(viewModel.isSubmitting ? "신청 중…" : "참여 신청") {
                        Task { await viewModel.submit() }
                    }
                    .disabled(viewModel.isSubmitting || viewModel.benches.isEmpty)
                }
                officialGuidance
            }
        }
        .navigationTitle("참여 신청")
        .task { await viewModel.load() }
    }
    private var officialGuidance: some View {
        Section("POSTECH 공식 기부 절차") {
            Text("기부금은 학교의 기존 공식 절차로 납입합니다. 앱은 기부금을 직접 받지 않습니다.")
            Link("공식 기부 사이트 열기", destination: OfficialDonationWebsite.url)
        }
    }
}
