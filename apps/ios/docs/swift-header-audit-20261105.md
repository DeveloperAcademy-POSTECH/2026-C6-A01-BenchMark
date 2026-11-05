# Swift 헤더 정리 — 2026-11-05

Git 최초 생성 커밋의 작성자 `DevDon-iOS`와 최초 원본의 `Created by 이돈혁`을 함께 확인한 50개 파일을 전체 헤더로 정리했다. 다른 작성자 또는 최초 작성자가 불명확한 파일은 수정하지 않았다. 기존에 완성된 헤더도 보존했다.

사용자 결정에 따라 원본 생성일이 없는 파일은 최초 생성 커밋일을 생성일로 표기했다. 파일명·프로젝트/타깃명·작성자·날짜를 포함하며 날짜 형식은 주변 Swift 헤더의 `M/d/yy`를 따른다.

50개 파일의 헤더 아래 본문이 기존 커밋과 동일함을 검사했고 각 파일에 `xcrun swiftc -frontend -parse`를 실행해 모두 통과했다. `git diff --check`도 통과했다. 주석 변경이므로 앱 빌드·실기기 검사는 추가 실행하지 않았다. 개인 서명 프로젝트 파일은 커밋 대상에서 제외한다.

| 파일 | 생성일 | 최초 생성 커밋 |
| --- | --- | --- |
| `apps/ios/OiDonation/Data/Networking/OiAccountMerge.swift` | 11/3/26 | `15fbd6a` |
| `apps/ios/OiDonation/Data/Networking/OiAppleAuthentication.swift` | 11/3/26 | `fe464c0` |
| `apps/ios/OiDonation/Data/Networking/OiAuthentication.swift` | 10/28/26 | `31520d5` |
| `apps/ios/OiDonation/Data/Networking/OiDraftVault.swift` | 10/28/26 | `31520d5` |
| `apps/ios/OiDonation/Data/Networking/OiServiceAPI.swift` | 10/28/26 | `31520d5` |
| `apps/ios/OiDonation/Data/Networking/OiServiceModels.swift` | 10/28/26 | `31520d5` |
| `apps/ios/OiDonation/Domain/Routing/AppClipLink.swift` | 10/22/26 | `5b204da` |
| `apps/ios/OiDonation/Features/AR/Models/ARSessionRecovery.swift` | 10/28/26 | `2091dd2` |
| `apps/ios/OiDonation/Features/AR/Services/Recording/ARVideoRecoveryStore.swift` | 11/3/26 | `25092b5` |
| `apps/ios/OiDonation/Features/AR/Views/Camera/Components/ARRecoveryPanel.swift` | 10/28/26 | `4bcd54f` |
| `apps/ios/OiDonation/Features/NFC/NFCWriteRequest.swift` | 10/22/26 | `46d8814` |
| `apps/ios/OiDonation/Features/NFC/NFCWriteView.swift` | 10/22/26 | `64b86f0` |
| `apps/ios/OiDonation/Features/NFC/NFCWriter.swift` | 10/22/26 | `46d8814` |
| `apps/ios/OiDonation/Features/Profile/MYCardArtwork.swift` | 10/30/26 | `6b2c75f` |
| `apps/ios/OiDonation/Features/Profile/MYCollectionView.swift` | 10/28/26 | `360bbc1` |
| `apps/ios/OiDonation/Features/Profile/MYFarmView.swift` | 10/28/26 | `360bbc1` |
| `apps/ios/OiDonation/Features/Profile/MYLibraryStore.swift` | 10/30/26 | `6b2c75f` |
| `apps/ios/OiDonation/Features/Profile/MYSettingsView.swift` | 10/30/26 | `36c85a7` |
| `apps/ios/OiDonation/Features/Profile/MYWorkshopView.swift` | 10/28/26 | `360bbc1` |
| `apps/ios/OiDonation/Features/Profile/OiAccountConnectionFlow.swift` | 11/3/26 | `f75324b` |
| `apps/ios/OiDonation/Features/Profile/OiAccountMergeView.swift` | 11/3/26 | `f75324b` |
| `apps/ios/OiDonation/Features/Profile/OiAppleSignInButton.swift` | 11/3/26 | `fe464c0` |
| `apps/ios/OiDonation/Features/Profile/OiConnectionStatus.swift` | 10/28/26 | `e8ef14d` |
| `apps/ios/OiDonation/Features/Profile/OiRemoteStore.swift` | 10/28/26 | `e8ef14d` |
| `apps/ios/OiDonation/Features/Profile/OiStoryEditor.swift` | 10/28/26 | `e8ef14d` |
| `apps/ios/OiDonationClip/Views/ARGame/ARGameHUD.swift` | 11/2/26 | `51de5ad` |
| `apps/ios/OiDonationClip/Views/ARGame/CucumberArtwork.swift` | 11/2/26 | `51de5ad` |
| `apps/ios/OiDonationTests/OiRemoteStoreTests.swift` | 10/28/26 | `e8ef14d` |
| `apps/ios/Tests/ARCameraLifecycleChecks.swift` | 10/28/26 | `230830c` |
| `apps/ios/Tests/ARCameraLifecycleFakes.swift` | 10/28/26 | `230830c` |
| `apps/ios/Tests/ARGameVisualChecks.swift` | 11/2/26 | `c195fc0` |
| `apps/ios/Tests/ARRecoveryChecks.swift` | 10/28/26 | `2091dd2` |
| `apps/ios/Tests/ARVideoRecoveryChecks.swift` | 11/3/26 | `25092b5` |
| `apps/ios/Tests/AppClipFontChecks.swift` | 11/2/26 | `182aefc` |
| `apps/ios/Tests/AppClipInvocationChecks.swift` | 10/22/26 | `5b204da` |
| `apps/ios/Tests/AppClipPublicStoryChecks.swift` | 11/2/26 | `182aefc` |
| `apps/ios/Tests/CollageGeometryChecks.swift` | 10/21/26 | `a36d9a0` |
| `apps/ios/Tests/CollageImageChecks.swift` | 10/21/26 | `ca2c3d8` |
| `apps/ios/Tests/MYDemoChecks.swift` | 10/28/26 | `d477f89` |
| `apps/ios/Tests/NFCWriteRequestChecks.swift` | 10/22/26 | `46d8814` |
| `apps/ios/Tests/OiAccountConnectionFlowChecks.swift` | 11/3/26 | `f75324b` |
| `apps/ios/Tests/OiAppleExchangeChecks.swift` | 11/3/26 | `fe464c0` |
| `apps/ios/Tests/OiDraftAdoptionChecks.swift` | 11/3/26 | `d7f347a` |
| `apps/ios/Tests/OiDraftRecoveryChecks.swift` | 11/3/26 | `d7f347a` |
| `apps/ios/Tests/OiServiceChecks.swift` | 10/28/26 | `31520d5` |
| `apps/ios/Tests/PhotoTest/CollageCanvas.swift` | 10/21/26 | `d93ab61` |
| `apps/ios/Tests/PhotoTest/CollageGeometry.swift` | 10/21/26 | `a36d9a0` |
| `apps/ios/Tests/PhotoTest/CollageImageService.swift` | 10/21/26 | `a36d9a0` |
| `apps/ios/Tests/PhotoTest/PhotoCollageEditor.swift` | 10/21/26 | `d93ab61` |
| `apps/ios/Tests/PhotoTest/PhotoTestView.swift` | 10/21/26 | `d93ab61` |
