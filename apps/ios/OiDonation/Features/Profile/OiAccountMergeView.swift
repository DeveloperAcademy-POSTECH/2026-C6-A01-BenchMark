// Created by 이돈혁

import SwiftUI

struct OiAccountMergeView: View {
    let remote: OiRemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var googleAuthentication = OiGoogleAuthentication()
    @State private var appleAuthentication = OiAppleAuthentication()
    @State private var flow: OiAccountConnectionFlow
    @State private var preview: OiMergePreview?
    @State private var consent = false
    @State private var confirming = false
    @State private var confirmationStarted = false
    @State private var completed = false
    @State private var status: String?
    @State private var failure: String?
    @State private var actionTask: Task<Void, Never>?
    @State private var actionID: UUID?
    @State private var action: Action?
    @State private var visible = false
    @State private var completion: Completion?

    private enum Completion: Equatable { case alreadyConnected, addedMethod, mergedRecords }
    private enum Action {
        case currentAuthentication, additionalAuthentication, preview, confirm

        var description: String {
            switch self {
            case .currentAuthentication: "현재 계정 확인 중"
            case .additionalAuthentication: "추가 로그인 확인 중"
            case .preview: "계정과 기록 확인 중"
            case .confirm: "계정 처리 결과 확인 중"
            }
        }
    }

    private var busy: Bool { actionTask != nil }
    private var addingMethod: Bool { flow.mode == .addLoginMethod }
    private var title: String { addingMethod ? "로그인 방법 추가" : "기존 계정 통합" }
    private var completionTitle: String {
        switch completion {
        case .alreadyConnected: "이미 현재 계정에 연결된 로그인 방법입니다."
        case .addedMethod: "현재 계정에 로그인 방법을 추가했습니다."
        case .mergedRecords: "기존 계정 통합을 완료했습니다."
        case nil: "계정 확인을 완료했습니다."
        }
    }
    private var canStart: Bool {
        visible && !busy && !remote.isBusy && !remote.isOperator && remote.account != nil && !completed
    }
    init(remote: OiRemoteStore, mode: OiAccountConnectionMode = .mergeExisting) {
        self.remote = remote
        _flow = State(initialValue: OiAccountConnectionFlow(mode: mode))
    }

    var body: some View {
        Form {
            if completed {
                Section {
                    Label(completionTitle, systemImage: "checkmark.circle")
                    Text(completion == .alreadyConnected ? "현재 계정의 로그인 방법으로 바로 사용할 수 있습니다." : "현재 계정과 기록을 계정 화면에서 확인할 수 있습니다.")
                    Button("완료") { dismiss() }
                }
            } else if remote.account == nil {
                Section { Text("현재 계정으로 로그인한 뒤 로그인 방법 연결을 시작해 주세요.") }
            } else if remote.isOperator {
                Section { Text("운영자 계정은 기존 계정 통합을 이용할 수 없습니다.") }
            } else if !remote.isAccountMergeAvailable && !confirmationStarted {
                Section { Text("서버의 계정 연결 준비 상태를 확인하지 못했습니다. 계정 화면에서 다시 불러온 뒤 이용해 주세요.") }
            } else {
                explanation
                currentAuthentication
                if flow.currentProof != nil { additionalAuthentication }
                if flow.pair != nil { representativeSelection }
                if let preview { previewSection(preview) }
            }
            if let action {
                Section {
                    ProgressView(action == .confirm && addingMethod ? "로그인 방법 추가 결과 확인 중" : action.description)
                    Button("작업 취소") { cancelAction() }
                }
            }
            if let status {
                Section { Text(status).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
            }
            if let failure {
                Section { Label(failure, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { visible = true }
        .onDisappear {
            visible = false
            actionID = nil
            actionTask?.cancel()
            actionTask = nil
            action = nil
            flow.clearProofs()
            clearPreview()
        }
        .onChange(of: remote.account?.id) { _, _ in
            guard !completed, action != .confirm else { return }
            actionID = nil
            actionTask?.cancel()
            actionTask = nil
            action = nil
            flow.clearProofs()
            clearPreview()
            status = "로그인 계정이 변경되었습니다. 현재 계정 확인부터 다시 시작해 주세요."
            failure = nil
        }
        .confirmationDialog(addingMethod ? "이 로그인 방법을 현재 계정에 추가할까요?" : "선택한 대표 계정으로 통합할까요?", isPresented: $confirming, titleVisibility: .visible) {
            Button(addingMethod ? "로그인 방법 추가" : "확인하고 통합") { confirmMerge() }
            Button("취소", role: .cancel) { }
        } message: {
            Text(addingMethod ? "현재 계정의 닉네임·학교·기록을 유지하며 추가한 로그인 방법으로 같은 계정을 이용할 수 있습니다." : "대표 계정의 닉네임과 학교를 유지하고 두 계정의 앱 기록을 합칩니다. 이 화면에서 통합을 되돌릴 수 없습니다.")
        }
    }

    private var explanation: some View {
        Section("진행 전 확인") {
            Text(addingMethod ? "현재 계정을 다시 확인한 뒤 추가할 로그인 방법으로 인증해 주세요. 이미 사용 중인 별도 계정이면 같은 인증을 이어서 기록 통합 내용을 확인합니다." : "현재 계정과 다른 기존 계정을 확인해 앱 기록을 하나의 대표 계정으로 합칩니다. 별도 기록이 없는 새 로그인 방법이면 현재 계정에 추가할 수 있습니다.")
            Text("추가 인증을 취소하거나 실패해도 현재 앱 로그인은 바뀌지 않습니다. 계정 확인 후 로그인 방법 추가 또는 기록 통합 내용을 안내합니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var currentAuthentication: some View {
        Section("1. 현재 계정 다시 확인") {
            Text(remote.account?.email ?? remote.profile?.nickname ?? "현재 로그인한 계정")
            if let currentProof = flow.currentProof { verifiedAccount(currentProof) }
            authenticationButtons(current: true)
        }
    }

    private var additionalAuthentication: some View {
        Section(addingMethod ? "2. 추가할 로그인 방법 확인" : "2. 통합할 다른 기존 계정 확인") {
            Text("추가로 사용할 로그인 방법이나 다른 기존 계정으로 인증해 주세요.").font(.footnote).foregroundStyle(.secondary)
            if let additionalProof = flow.additionalProof { verifiedAccount(additionalProof) }
            authenticationButtons(current: false)
        }
    }

    private func authenticationButtons(current: Bool) -> some View {
        Group {
            Button(current ? "Google로 현재 계정 확인" : "Google로 추가 로그인 확인") {
                authenticate(current: current, using: googleAuthentication)
            }
            .frame(minHeight: 44)
            OiAppleSignInButton { authenticate(current: current, using: appleAuthentication) }
                .frame(minHeight: 44)
                .accessibilityLabel(current ? "Apple로 현재 계정 확인" : "Apple로 추가 로그인 확인")
        }
        .disabled(busy || remote.isBusy || confirmationStarted)
    }

    private func verifiedAccount(_ proof: OiSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(proof.user.email ?? "인증한 계정", systemImage: "checkmark.circle")
            Text("계정 구분: \(proof.user.id.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var representativeSelection: some View {
        Section(!flow.hasClassifiedAdditional ? "3. 연결 내용 확인" : (addingMethod ? "3. 현재 계정에 추가" : "3. 대표 계정 선택")) {
            if flow.canChooseRepresentative {
                Picker("기록을 모을 대표 계정", selection: Binding(get: { flow.representative }, set: { choice in
                    if flow.chooseRepresentative(choice) { clearPreview() }
                })) {
                    Text("현재 계정").tag(OiAccountConnectionFlow.Representative.current)
                    Text("추가로 인증한 계정").tag(OiAccountConnectionFlow.Representative.additional)
                }
                .disabled(busy || remote.isBusy || confirmationStarted)
            } else if flow.hasClassifiedAdditional {
                Text("현재 계정의 닉네임·학교·기록을 계속 사용합니다.")
            } else {
                Text("추가로 인증한 계정의 기록을 확인한 뒤 로그인 방법 추가 또는 기록 통합을 안내합니다.")
            }
            if let pair = flow.pair { verifiedAccount(pair.target) }
            if flow.hasClassifiedAdditional {
                Text(addingMethod ? "별도 기록이 없는 로그인 방법을 현재 계정에 추가합니다. 최종 동의 전에는 추가를 확정하지 않습니다." : "대표 계정의 닉네임·학교를 유지합니다. 이야기와 증빙의 검토 상태, 작성 승인 기록은 그대로 유지합니다. 운영자 계정은 통합 대상에서 제외됩니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !confirmationStarted {
                Button(!flow.hasClassifiedAdditional ? "연결 내용 확인" : (addingMethod ? "로그인 방법 추가 내용 확인" : "통합할 기록 다시 확인")) { loadPreview() }
                    .disabled(busy || remote.isBusy)
            } else {
                Text("이미 확인 요청을 보냈습니다. 응답이 끊겼다면 같은 계정과 요청으로 결과를 다시 확인해 주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func previewSection(_ preview: OiMergePreview) -> some View {
        Section(addingMethod ? "4. 로그인 방법 추가 확인" : "4. 기록과 동의 확인") {
            LabeledContent("이야기", value: "\(preview.counts.stories)개")
            LabeledContent("수집한 오이", value: "\(preview.counts.collections)개")
            LabeledContent("즐겨찾기", value: "\(preview.counts.favorites)개")
            LabeledContent("기부 증빙", value: "\(preview.counts.evidence)건")
            LabeledContent("작성 승인", value: "\(preview.counts.grants)건")
            Text(addingMethod ? "추가한 로그인 방법으로 계속 이용할 현재 계정의 기록입니다." : "서버에서 확인한 두 계정의 기록입니다. 로그인 계정 자체를 삭제하는 작업은 아닙니다.")
                .font(.footnote).foregroundStyle(.secondary)
            if let expires = expiration(of: preview) {
                LabeledContent("확인 정보 유효 시간") { Text(expires, style: .time) }
            }
            Toggle(addingMethod ? "이 로그인 방법으로 현재 계정의 기록을 사용할 수 있게 추가하는 데 동의합니다." : "대표 계정과 통합할 기록, 상태 유지 및 되돌릴 수 없음을 확인했습니다.", isOn: $consent)
                .disabled(busy || confirmationStarted)
            Button(confirmationStarted ? "같은 요청 결과 다시 확인" : (addingMethod ? "이 로그인 방법을 현재 계정에 추가" : "이 계정으로 통합")) {
                if confirmationStarted { confirmMerge() }
                else { confirming = true }
            }
            .disabled(!consent || busy || remote.isBusy)
        }
    }

    private func authenticate(current: Bool, using provider: any OiAuthenticating) {
        guard canStart, !confirmationStarted else { return }
        resetPreview()
        run(current ? .currentAuthentication : .additionalAuthentication) { attempt in
            let proof = try await remote.authenticateAdditional(using: provider)
            try checkActive(attempt)
            if current {
                try await remote.validateCurrentIdentity(proof)
                try checkActive(attempt)
                flow.acceptCurrentProof(proof)
                if let additional = flow.additionalProof {
                    if try await finishIfAlreadyConnected(additional, attempt: attempt) { return }
                    try await requestPreview(attempt: attempt)
                } else {
                    status = "현재 계정을 확인했습니다."
                }
            } else {
                if try await finishIfAlreadyConnected(proof, attempt: attempt) { return }
                flow.acceptAdditionalProof(proof)
                try await requestPreview(attempt: attempt)
            }
        }
    }

    private func loadPreview() {
        guard canStart, !confirmationStarted, flow.pair != nil else { return }
        resetPreview()
        run(.preview) { attempt in
            try await requestPreview(attempt: attempt)
        }
    }

    private func finishIfAlreadyConnected(_ proof: OiSession, attempt: UUID) async throws -> Bool {
        let matches = try await remote.additionalAccountMatchesCurrent(proof)
        try checkActive(attempt)
        guard matches else { return false }
        completion = .alreadyConnected
        completed = true
        flow.clearProofs()
        clearPreview()
        return true
    }

    private func requestPreview(attempt: UUID) async throws {
        guard let pair = flow.pair else { throw OiServiceError.signInRequired }
        let operation = flow.operationID
        action = .preview
        let result = try await remote.previewMerge(target: pair.target, source: pair.source, operationID: operation)
        try checkActive(attempt)
        flow.resolvePreview(sourceIsNew: result.sourceIsNew)
        preview = result
        status = addingMethod
            ? "별도 기록이 없는 로그인 방법입니다. 현재 계정에 추가할 수 있습니다."
            : "이미 사용 중인 별도 계정입니다. 인증을 다시 하지 않고 기록 통합 내용을 확인해 주세요."
    }

    private func confirmMerge() {
        guard canStart, consent, let pair = flow.pair, let preview else { return }
        guard confirmationStarted || expiration(of: preview).map({ $0 > Date() }) == true else {
            resetPreview()
            failure = "확인 정보가 만료됐습니다. 계정과 기록을 다시 확인해 주세요."
            return
        }
        let operation = flow.operationID
        let expectedCompletion: Completion = addingMethod ? .addedMethod : .mergedRecords
        confirmationStarted = true
        run(.confirm) { attempt in
            _ = try await remote.confirmMerge(target: pair.target, source: pair.source, preview: preview, operationID: operation)
            // A confirmed server receipt is completion, even if later list refresh was canceled.
            guard visible, actionID == attempt else { return }
            completion = expectedCompletion
            completed = true
            flow.clearProofs()
            self.preview = nil
            status = remote.loadError == nil ? nil : "계정 처리는 완료됐지만 기록을 다시 불러오지 못했습니다. 계정 화면에서 다시 불러오기를 이용해 주세요."
        }
    }

    private func run(_ next: Action, operation: @escaping (UUID) async throws -> Void) {
        guard canStart else { return }
        let attempt = UUID()
        actionID = attempt
        action = next
        failure = nil
        status = nil
        actionTask = Task { @MainActor in
            defer {
                if actionID == attempt { actionTask = nil; action = nil; actionID = nil }
            }
            do { try await operation(attempt) }
            catch OiMergeFailure.reviewChanged {
                guard visible, actionID == attempt else { return }
                clearPreview()
                flow.reviewChanged()
                status = "계정이나 기록이 변경됐습니다. 추가 인증을 다시 하지 않고 최신 내용을 확인해 주세요."
            }
            catch OiMergeFailure.reauthenticationRequired {
                guard visible, actionID == attempt else { return }
                clearPreview()
                flow.reviewChanged()
                failure = OiMergeFailure.reauthenticationRequired.localizedDescription
            }
            catch {
                guard visible, actionID == attempt else { return }
                if Task.isCancelled || OiServiceFailure.isCancellation(error) {
                    status = next == .confirm
                        ? "요청 확인을 중단했습니다. 서버 처리 여부는 같은 요청의 결과를 다시 확인해 주세요."
                        : "작업을 취소했습니다. 현재 앱 로그인은 유지됩니다."
                } else {
                    failure = error.localizedDescription
                }
            }
        }
    }

    private func cancelAction() {
        actionTask?.cancel()
        status = "작업 취소를 기다리고 있습니다."
    }

    private func checkActive(_ attempt: UUID) throws {
        try Task.checkCancellation()
        guard visible, actionID == attempt else { throw CancellationError() }
    }

    private func resetPreview() {
        clearPreview()
        flow.resetOperation()
    }

    private func clearPreview() {
        preview = nil
        consent = false
        confirming = false
        failure = nil
        status = nil
        confirmationStarted = false
    }

    private func expiration(of preview: OiMergePreview) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: preview.expiresAt) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: preview.expiresAt)
    }
}

#Preview {
    NavigationStack { OiAccountMergeView(remote: OiRemoteStore()) }
}
