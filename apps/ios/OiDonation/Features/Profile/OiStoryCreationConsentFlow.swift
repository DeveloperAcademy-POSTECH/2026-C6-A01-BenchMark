import SwiftUI

/// Visiting a screen does not accept terms; the editor checks consent before submission.
struct OiStoryCreationConsentFlow: View {
    let remote: OiRemoteStore
    var continuation: OiStoryContinuationIntent? = nil
    var onFinish: (() -> Void)?

    var body: some View {
        OiStoryEditor(remote: remote, initialStep: .consent, continuation: continuation, onFinish: onFinish)
    }
}
