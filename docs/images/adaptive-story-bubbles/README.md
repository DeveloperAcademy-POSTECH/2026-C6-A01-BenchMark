# 실제 이야기 좌표 기반 지도 버블 검증

2026-11-18 · #478 · Xcode 27.1 / iPhone 18 Pro, iOS 27.0 Simulator. 배포 대상 iOS 26.2와 Swift 5 모드는 유지한다.

`CampusMapInteractionTests/testStoryBubblesFollowCoordinatesRefreshAndOpenExactMembers`가 실제 캠퍼스 메시와 대운동장 POI 좌표를 사용해 캡처했다. `regionID=student`인 가상 이야기 1개만 제공해 다른 장소에 빈 버블이 생기지 않고 대운동장의 실제 투영 좌표에 숫자 1이 표시되는지 검사한다. 공개 서비스에 테스트 데이터를 넣지 않는다.

- [375×667](story-bubble-stadium-375.png)
- [402×874](story-bubble-stadium-402.png)
- [440×956](story-bubble-stadium-440.png)

스크린샷은 XCTest의 RealityKit snapshot과 실제 UIKit 버블을 합성한 원본을 논리 해상도로 축소했다. 카드·본문·계정 및 전체 홈 헤더를 검증하는 캡처가 아니다.

## 실행한 검사

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/oi-478-clang-cache sh apps/ios/Tests/run-campus-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-campus-label-checks.sh
```

두 명령이 통과했다. 실제 좌표의 장소명, 빈 군집, 동일 좌표 병합, 2,000개 입력 집계, 역방향 핀치·연속 전환·Reduce Motion·카메라 관성 회귀를 포함한다. 기존 캠퍼스 검사 스크립트의 누락된 `OiContentSafetyStore` 소스 의존성도 포함했다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks \
  -destination 'platform=iOS Simulator,id=ED67A555-0C6E-43E3-95FB-1FE3FDA1C6E9' \
  -derivedDataPath /private/tmp/oi-478-derived \
  -resultBundlePath /private/tmp/oi-478-tests.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:OiDonationTests/CampusMapInteractionTests/testStoryBubblesFollowCoordinatesRefreshAndOpenExactMembers \
  -only-testing:OiDonationTests/CampusMapInteractionTests/testOverviewPinchReversalAndTilt \
  -only-testing:OiDonationTests/CampusMapInteractionTests/testReleaseSettlesOverzoomAndCanBeInterrupted \
  -only-testing:OiDonationTests/CampusMapInteractionTests/testPublicOiOnlyAppearsWithStoryListAndHidesWhenClosed \
  -only-testing:OiDonationTests/CampusMapInteractionTests/testRegionBadgeRendersCompleteYangjinDigits \
  -only-testing:OiDonationTests/CampusMapInteractionTests/testRegionListDragKeepsPanelOwnershipDuringReversal \
  -only-testing:OiDonationTests/OiRemoteStoreTests/testStoryLocationUsesCoordinatesInsteadOfSavedRegion \
  CODE_SIGNING_ALLOWED=NO
```

최초 실행은 기존 회귀 5개와 위치명 검사 1개가 통과했다. 새 검사에서 교육지구 버튼까지 숫자 버블로 집계한 테스트 범위를 수정한 뒤 다음 명령으로 해당 검사 1개를 다시 실행해 통과했다. 제품 코드를 약화하거나 검사를 제거하지 않았다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks \
  -destination 'platform=iOS Simulator,id=ED67A555-0C6E-43E3-95FB-1FE3FDA1C6E9' \
  -derivedDataPath /private/tmp/oi-478-derived \
  -resultBundlePath /private/tmp/oi-478-verified.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:OiDonationTests/CampusMapInteractionTests/testStoryBubblesFollowCoordinatesRefreshAndOpenExactMembers \
  CODE_SIGNING_ALLOWED=NO
```

총 7개의 서로 다른 테스트가 최종적으로 통과했고, 본 앱·App Clip·테스트 타깃이 빌드됐다. 기존 Swift 6 언어 모드 전환 관련 경고와 시뮬레이터 그래픽 경고는 남아 있다. 실기기 설치·App Store 배포는 수행하지 않았다.

## 리소스 정리

작업 전용 시뮬레이터 `ED67A555-0C6E-43E3-95FB-1FE3FDA1C6E9`는 테스트 직후 종료·삭제했고 해당 ID의 프로세스와 기기 목록 잔존이 없음을 확인했다. XCTest의 작업 창은 각 테스트의 `defer`에서 숨김뿐 아니라 root controller·window scene 연결까지 해제했다. GUI 자동화·브라우저·입력 장치 조작은 사용하지 않았다. 최대 동시 작업 리소스는 시뮬레이터·빌드/테스트·별도 네이티브 검사 3개 그룹이다.
