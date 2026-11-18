import SwiftUI

/// Story creation starts at STEP 2 with the editor's automatic required-clause acceptance.
struct OiStoryCreationConsentFlow: View {
    let remote: OiRemoteStore
    var continuation: OiStoryContinuationIntent? = nil
    var onFinish: (() -> Void)?

    var body: some View {
        OiStoryEditor(remote: remote, initialStep: .story, continuation: continuation, onFinish: onFinish)
    }
}
