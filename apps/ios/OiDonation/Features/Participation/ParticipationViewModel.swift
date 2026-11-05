import Foundation
import Observation

@MainActor @Observable
final class ParticipationViewModel {
    var draft = ParticipationDraft(benchID: "", message: "", story: "")
    private(set) var benches: [Bench] = []
    private(set) var application: ParticipationApplication?
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private let benchesRepository: any BenchRepository
    private let repository: any ParticipationRepository
    private var submissionKey = UUID()
    private var submittedDraft: ParticipationDraft?

    init(benches: any BenchRepository, participation: any ParticipationRepository) {
        benchesRepository = benches
        repository = participation
    }
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { benches = try await benchesRepository.fetchBenches() }
        catch is CancellationError { }
        catch { errorMessage = "벤치를 불러오지 못했어요. 다시 시도해 주세요." }
    }
    func submit() async {
        guard !isSubmitting, application == nil else { return }
        errorMessage = nil
        do {
            let validated = try draft.validated()
            guard benches.contains(where: { $0.id == validated.benchID }) else {
                throw ParticipationError.missingBench
            }
            if submittedDraft != validated { submissionKey = UUID(); submittedDraft = validated }
            isSubmitting = true
            defer { isSubmitting = false }
            application = try await repository.submit(validated, idempotencyKey: submissionKey)
        } catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }
}
