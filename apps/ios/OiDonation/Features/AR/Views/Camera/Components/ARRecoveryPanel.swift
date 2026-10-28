// Created by 이돈혁

import SwiftUI

struct ARRecoveryPanel: View {
    let issue: ARRecoveryIssue
    let starting: Bool
    var closing = false
    let openSettings: () -> Void
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 16) {
                explanation
                recoveryAction
                closeButton
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 16) {
                        explanation
                        recoveryAction
                    }
                }
                closeButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private var explanation: some View {
        VStack(spacing: 16) {
            Label(issue.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(issue.message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var recoveryAction: some View {
        if closing {
            ProgressView("촬영 마무리 중…")
        } else if starting {
            ProgressView("카메라 다시 준비 중…")
        } else if issue.canOpenSettings {
            Button(action: openSettings) {
                Text("설정 열기").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent)
        } else if issue.canRetry {
            Button(action: retry) {
                Text("다시 시도").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent)
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Text("AR 카메라 닫기").frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.bordered)
    }
}

#Preview("권한 거부 · 작은 화면", traits: .fixedLayout(width: 320, height: 568)) {
    ARRecoveryPanel(issue: .cameraDenied, starting: false, openSettings: {}, retry: {}, close: {})
        .frame(maxWidth: 380, maxHeight: 428)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("세션 실패 · 기준 화면", traits: .fixedLayout(width: 402, height: 874)) {
    ARRecoveryPanel(issue: .sessionFailure("카메라 연결이 끊겼습니다."), starting: false,
                    openSettings: {}, retry: {}, close: {})
        .frame(maxWidth: 380, maxHeight: 734)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("큰 글자 · 큰 화면", traits: .fixedLayout(width: 440, height: 956)) {
    ARRecoveryPanel(issue: .cameraDenied, starting: false, openSettings: {}, retry: {}, close: {})
        .frame(maxWidth: 380, maxHeight: 816)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
