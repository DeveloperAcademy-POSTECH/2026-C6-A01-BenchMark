import SwiftUI

struct OiStoryCreationConsentFlow: View {
    let remote: OiRemoteStore
    var onFinish: (() -> Void)?

    @State private var showingEditor = false
    @State private var showingApprovalNotice = false

    var body: some View {
        OiStoryConsentView(
            clauses: OiStoryConsentClause.figmaDrafts,
            onContinue: continueToEditor
        )
        .navigationDestination(isPresented: $showingEditor) {
            OiStoryEditor(remote: remote, onFinish: onFinish)
        }
        .alert("작성 승인이 필요해요", isPresented: $showingApprovalNotice) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("유효한 이야기 작성 승인을 확인한 뒤 다시 시도해 주세요.")
        }
    }

    private func continueToEditor() {
        if remote.canStartStory {
            showingEditor = true
        } else {
            showingApprovalNotice = true
        }
    }
}
