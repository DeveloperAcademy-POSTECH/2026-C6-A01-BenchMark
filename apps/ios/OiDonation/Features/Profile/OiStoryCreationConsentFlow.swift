import SwiftUI

/// Visiting a screen does not accept terms; the editor checks consent before submission.
struct OiStoryCreationConsentFlow: View {
    let remote: OiRemoteStore
    var onFinish: (() -> Void)?

    var body: some View {
        OiStoryEditor(remote: remote, initialStep: .consent, onFinish: onFinish)
    }
}
