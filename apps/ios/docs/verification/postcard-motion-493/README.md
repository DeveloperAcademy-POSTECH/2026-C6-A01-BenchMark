# 포토카드 기울기 효과 검증 — #493

2026-11-18. App Clip은 UIKit 모션 효과, 본 앱의 Figma `5887:10243` 접수 완료 카드는 Core Motion을 사용한다. 두 효과는 축별 최대 4°이며 기존 카드 이미지·크기·뒤집기를 유지한다. 본 앱의 다른 카드 화면으로 Core Motion을 확대 적용하지 않는다.

## 검증 환경과 결과

- Xcode 27.1 / Swift 6.4. 프로젝트의 Swift 5 모드와 iOS 26.2 배포 대상을 유지했다.
- 전용 iPhone 17 Pro / iOS 26.5 Simulator를 사용했다.
- `OiDonation` 및 포함된 `OiDonationClip` 시뮬레이터 빌드 성공.
- 최신 `develop`의 세로 모드 고정 변경을 통합한 뒤 `OiFlowChecks`의 아래 4개 테스트 성공, 실패 0개.
- 완료 화면 402×874·375×667·440×956 캡처, 공유 스크래치 화면의 공개 전·후 표시, 기존 가로 뒤집기 판정을 검사했다.
- 독립 모션 검사 성공: 상대 quaternion 기준 자세, 짧은 회전 경로, 시간 기반 평활화, ±4° 제한, 초기화, 잘못된·역순 샘플, 화면 방향 매핑.
- UIKit 효과 설치 중복 방지·비활성·window 분리·representable 해제·내부 flip transform 보존을 검사했다. 실제 SwiftUI → UIKit → SwiftUI 경로에서 Dynamic Type 전달과 활성 전환 중 `@State` 식별자 유지도 검사했다.
- 정지/기울기 앞면 320·402·440pt와 기울인 뒷면, 총 7개 렌더를 생성했다. 보간기의 ±4° 끝점과 실제 layer 회전을 검사하고 정지 대비 27,531 / 30,254 / 30,237픽셀 변화로 기울기가 보임을 확인했다.
- 기존 코드의 Swift 동시성 및 App Intents 메타데이터 경고는 남아 있다. 변경한 모션 소스의 컴파일 경고는 없었다.

## 실행한 명령

저장소 루트에서 실행했다. 아래 UDID는 이 작업에서 생성·삭제한 기기이므로 재실행할 때 새 전용 기기의 UDID로 바꾼다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/ios/OiDonation.xcodeproj -scheme OiDonation \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/benchmark-postcard-motion-493-build \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
sh apps/ios/Tests/run-postcard-motion-checks.sh \
  A7FB0DEC-77A3-4488-9486-146BB453F899 \
  /private/tmp/benchmark-postcard-motion-493-renders-environment

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks \
  -destination 'platform=iOS Simulator,id=A7FB0DEC-77A3-4488-9486-146BB453F899' \
  -derivedDataPath /private/tmp/benchmark-postcard-motion-493-build \
  -resultBundlePath /private/tmp/benchmark-postcard-motion-493-screens-final.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testPostcardMotionCompletionCaptures \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testScratchPostcardFullAppRevealedUnsaved \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testScratchPostcardFullAppStartsCovered \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testPostcardHorizontalFlipAndDate \
  CODE_SIGNING_ALLOWED=NO
```

로그는 `/private/tmp/benchmark-postcard-motion-493-build.log`, `/private/tmp/benchmark-postcard-motion-493-checks-environment.log`, `/private/tmp/benchmark-postcard-motion-493-screens-final.log`에 보존했다. `git diff --check`와 변경된 plist 검사도 통과했다.

## 이미지

가상 작성자와 기존 테스트 이미지를 사용했다. 완료 화면은 실제 프로덕션 뷰의 정지 캡처다. UIKit 예시는 프로덕션 모션 래퍼·FlipCard에 기존 테스트 이미지를 넣고 공식 보간기 끝점으로 기울인 **결정적 렌더**이며, 실제 센서가 동작했다는 증거가 아니다.

- [접수 완료 화면 402×874](completion-402x874.png)
- [UIKit 정지 앞면](card-front-static.png)
- [UIKit 기울기 앞면](card-front-tilted.png)
- [UIKit 기울기 뒷면 — 테스트 문구](card-back-tilted.png)

## 한계와 정리

Needs confirmation:

- 실제 App Clip 배포 환경에서 `UIInterpolatingMotionEffect`가 폰의 기울기에 반응하는지 확인해야 한다. [공식 UIKit API](https://developer.apple.com/documentation/uikit/uiinterpolatingmotioneffect)는 일반 동작을 설명하지만 App Clip 런타임 반응을 보장하지 않는다. [App Clip은 Core Motion을 지원하지 않는다](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip).
- 본 앱의 실제 기울기 방향·감도·배터리와 두 앱의 실제 동작 줄이기 전환을 iPhone에서 확인해야 한다. 시뮬레이터·합성 입력 결과와 구분한다.

화면 이탈·앱 비활성·동작 줄이기·가리는 시트에서 효과/센서 구독을 중단한다. 본 앱에 모션 사용 설명을 추가했으며 모션 데이터는 저장·전송하지 않는다.

작업 소유 동시 실행 리소스 그룹은 최대 2개였다(전용 시뮬레이터와 빌드/검증 작업). 검증 앱 `kr.ac.postech.benchmark.postcardmotionchecks` 및 테스트 호스트 `com.Spero.OiDonation` 제거를 확인한 뒤 전용 시뮬레이터 `A7FB0DEC-77A3-4488-9486-146BB453F899`를 종료·삭제하고 목록에서 사라진 것을 확인했다. 기록한 빌드·검증 프로세스 그룹의 잔여 프로세스는 0개였다. 캡처 helper의 hidden window 분리 검사도 통과했고 Computer Use/브라우저 세션은 생성하지 않았다. 기존 사용자 시뮬레이터와 앱은 조작하지 않았다.
