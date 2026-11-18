# 이야기 목록 그림자·오이 프리뷰 — #482

2026-11-18. Figma [`5400:7644`](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=5400-7644)의 카드 배치와 문구를 유지한다.

## 수정과 확인

- 카드 배경에만 그림자를 적용한다. 이름·태그·제목·프리뷰 내부는 그림자를 끈 렌더와 같은 픽셀이며 카드 바깥 그림자는 유지되는 것을 검사했다.
- 목록은 카드용 PNG·카드 회전·카드의 오이 숨김 설정과 분리된 현재 외형을 사용한다. 의상 선택·해제 및 기본 얼굴 적용은 `seedAppearance`를 보존해 명시적 로컬 기본 외형을 기록한다. 마지막 의상을 해제하면 과거 서버 의상보다 맨몸 상태가 우선하고, 서버 초안을 외형 변경 없이 열고 저장한 빈 설정은 서버 외형을 유지한다.
- seed는 정면으로 생성하고 구형 서버 이미지는 인증된 기존 로더로 읽는다. 모든 원본은 알파 여백 제거 후 150×234px(50×78pt @3x)에 맞춘다. 모델이 없는 구형 서버 PNG의 원래 방향은 보존한다.
- 목록 전체에서 하나의 캡처 surface를 순차 사용하고 캡처 완료·취소·화면 이탈·백그라운드에서 해제한다. 실제 두 seed 의상 캡처에서 동시에 한 개 이하의 `ARView`와 완료 후 숨은 surface가 없는 것을 확인했다.
- 계정별 이미지 캐시는 최대 8개로 제한하고 심기 전환의 첫 프레임부터 재사용한다. 계정 전환 후 늦은 이미지 응답 폐기, 재시도, 동일 source 재다운로드 방지도 검사했다.

## 실행 결과

Xcode 27.1(27A9275), iPhone 17 Pro / iOS 27.0 Simulator. 프로젝트의 iOS 26.2 배포 대상과 Swift 5 언어 모드는 변경하지 않았다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug \
  -destination 'platform=iOS Simulator,id=51006FA1-91B1-41F7-8533-E37312BBEB31' \
  -derivedDataPath /private/tmp/benchmark-story-preview-482-build \
  -resultBundlePath /private/tmp/benchmark-story-preview-482-final-tests.xcresult \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testStoryListCardShadowDoesNotAffectItsContents \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testStoryListPortraitUsesCurrentLookInsteadOfCardComposition \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testStoryListPortraitNormalizesTransparentMargins \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testStoryListPortraitLoadingCachesRetriesAndRejectsStaleAccounts \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testStoryListPortraitCacheReusesPixelsAcrossScreensAndIsBounded \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testStoryListCurrentSeedPortraitsCaptureSeriallyAndReleaseRenderers \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testStoryListSeedUICaptures \
  CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-my-checks.sh
git diff --check
```

7 tests, 0 failures / `TEST SUCCEEDED`. MY 모델 검사와 `git diff --check`도 통과했다. 위 시뮬레이터는 검증 후 종료·삭제했으므로 재실행 시 새 대상 ID와 결과 경로가 필요하다.

MY 보조 검사는 기존 스크립트에 누락된 seed·wardrobe 의존 소스를 포함했다. upstream `caae391e`가 검토중인 이야기를 네 칸 밖에도 보존하도록 변경한 뒤 남은 `count == 4` 기대값은 입력 개수와 전체 ID·순서 보존 검사로 바로잡았다. 4개 편집 칸과 `isFull` 검사는 유지한다.

## 캡처

- [실제 정면 seed·후드 의상](story-list-current-front-portraits-402x874.png)
- [글자 그림자 없는 공통 카드](card-background-shadow.png)
- [375×667](story-list-seed-reference-375x667.png), [440×956](story-list-seed-reference-440x956.png), [접근성 최대 글씨](story-list-seed-reference-accessibility5.png)

가상 작성자와 테스트 전용 외형을 사용했다. 운영 계정·운영 DB·배포는 변경하지 않았다. 실기기 및 실제 서버 계정의 재로그인·다른 기기 복원은 검증하지 않았다. 수정 전에 이미 모든 필드가 비어 있던 로컬 설정은 미편집 복원과 마지막 의상 해제를 구분할 자료가 없어 서버 외형을 보존한다.

## 리소스 정리

최대 동시 작업 소유 리소스는 3개 그룹(전용 시뮬레이터, xcodebuild 테스트, MY 명령행 검사)이었다. 테스트 창은 기존 helper가 숨김 창까지 scene에서 분리했다. 최초 검증의 전용 기기 `214DC4DE-7E2A-4884-B066-42321E90A9C0`는 종료·삭제했고, 최종 복원 경계 검사에는 같은 이름의 기기 `51006FA1-91B1-41F7-8533-E37312BBEB31` 하나를 사용했다. 검증 후 이 기기도 종료·삭제하고 기록한 PID·작업 경로와 두 기기 ID로 잔여 프로세스·기기가 없는지 확인했다. 다른 작업의 기기·프로세스는 보존한다.
