# iOS 26 초기 버전 상태 모델 해제 — #222

iOS 26.3에서 계정 전환과 운영자 화면 검증 중 Swift 동시성 런타임의 `TaskLocal::StopLookupScope` 및 `swift_task_deinitOnExecutorImpl`에서 충돌했다. `MainActor` 기본 격리에서 합성된 해제 함수와 관련한 [Swift #88036](https://github.com/swiftlang/swift/issues/88036)의 재현 조건에 해당한다.

계정·운영자 상태 모델과 iOS 26.2까지 지원하는 App Clip의 진입·AR 상태 모델에 명시적인 `nonisolated deinit {}`을 둔다. 해제 경로만 바꾸며 상태 조회·변경의 `MainActor` 격리, 타이머·AR 종료 동작, 최소 지원 버전은 유지한다. 런타임 호환성을 위해 빈 본문을 유지한다.

검증은 iOS 26.3에서 `OiFlowChecks`의 계정/운영자 검사와 체험 화면/AR 윤곽 검사를 실행한다. 실제 기기 카메라 및 NFC 시험과 구분한다.
