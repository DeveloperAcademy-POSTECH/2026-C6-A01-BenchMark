# 커스텀 되돌리기·필수 스탬프 검증 — #483

2026-11-18. Xcode 27.1 / iOS 27.0 전용 시뮬레이터에서 검증했다. 저장소의 iOS 26.2 배포 대상과 Swift 5 언어 모드는 유지했다.

## 확인 결과

- 신규·미선택/잘못된 구형 스탬프를 1...12 중 하나로 보정하고 최초 선택을 저장한다. 재진입·Codable 복원·재탭·반복 초기화에서 유지된다.
- 카드 초기화는 내용 탭 선택·원본 사진·작성자·날짜를 유지하며 회색 단색·흰 로고·최초 스탬프·기본 배치·정면을 복원한다.
- 오이 초기화는 얼굴·몸체·구형/신형 의상·색상·사진 의상을 초기화한다. 내용과 카드 설정을 보존하고 파생 오이 이미지만 무효화한다. 기본 오이 모델을 카드의 이미지 원본으로 유지한다.
- 앞면 로고의 저장된 alpha가 0/0.5여도 완전 불투명하게 렌더한다. 로고 외 픽셀과 뒷면 로고·종이 불투명도는 유지된다.
- Figma `5400:11817`의 회색 14pt 밑줄 버튼을 공유해 카드 완료 위·오이 얼굴 위에 표시한다. 앞면 로고 불투명도 컨트롤은 없다.
- 375×667·402×874·440×956 화면 캡처 9장을 검토했다. 작은 화면의 편집 항목은 기존 스크롤로 접근한다.

## 실행 명령과 결과

저장소 루트에서 실행했다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-draft-recovery-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-oi-service-checks.sh
```

둘 다 종료 코드 0. 서비스 검사는 최초 sandbox의 Observation 매크로 실행 제한을 확인한 뒤 정상 실행 권한에서 통과했다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug \
  -destination 'platform=iOS Simulator,id=AF36E0C3-4EF3-4F3E-8870-F3C1B184BFC8' \
  -derivedDataPath /private/tmp/benchmark-customization-reset-483-build \
  -resultBundlePath /private/tmp/benchmark-customization-reset-483-final-results.xcresult \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testCustomizationStampDefaultsPersistAndRepair \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testCustomizationStampRetapKeepsOneSelection \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testCustomizationCardResetKeepsContentAndRestoresDefaults \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testCustomizationCucumberResetClearsAllOutfitsAndKeepsCard \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testCustomizationResetButtonsAndLogoCaptures \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testPostcardLogosPreserveUnderlyingArtwork \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testPostcardOpacityRenderingAndPersistence \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testPostcardRefreshPersistenceAndPrivacy \
  CODE_SIGNING_ALLOWED=NO
```

요청 관련 7개 통과. 추가 호환 검사 1개는 기존 테스트가 실제 `[theme, emotion]` 대신 `[emotion, theme]`를 전달해 실패했다. 입력을 `draft.postcardTags`로 정정하고 PNG 동일성 assertion은 유지했다. 다음 재검사에서 통과했다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug \
  -destination 'platform=iOS Simulator,id=AF36E0C3-4EF3-4F3E-8870-F3C1B184BFC8' \
  -derivedDataPath /private/tmp/benchmark-customization-reset-483-build \
  -resultBundlePath /private/tmp/benchmark-customization-reset-483-privacy-results.xcresult \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testPostcardRefreshPersistenceAndPrivacy \
  CODE_SIGNING_ALLOWED=NO
```

최종 관련 8개 모두 통과. `git diff --check` 통과. 별도 에이전트가 전체 변경을 읽기 전용으로 검토했다.

## 화면

| 크기 | 카드 로고 | 필수 스탬프 | 오이 |
| --- | --- | --- | --- |
| 375×667 | [보기](card-logo-375x667.png) | [보기](card-stamp-375x667.png) | [보기](cucumber-375x667.png) |
| 402×874 | [보기](card-logo-402x874.png) | [보기](card-stamp-402x874.png) | [보기](cucumber-402x874.png) |
| 440×956 | [보기](card-logo-440x956.png) | [보기](card-stamp-440x956.png) | [보기](cucumber-440x956.png) |

## 검증 한계·자원 정리

Needs confirmation:
- 실제 iPhone 터치·사진첩 저장·로그인 계정으로 공개 제출은 이번 검사에 포함하지 않았다.

작업 소유 실행 자원은 최대 동시 3개 그룹(전용 시뮬레이터·xcodebuild·서비스 CLI 검사)이었다. 모든 명령은 종료했고 전용 시뮬레이터 `AF36E0C3-4EF3-4F3E-8870-F3C1B184BFC8`는 Shutdown을 확인했다. 빌드/launchd_sim 잔존 프로세스 0개를 확인했다. 캡처 helper는 매번 소유 창을 scene에서 분리해 숨은 창까지 제거하고 기존 창의 key/visibility 보존을 assertion으로 검사한다. Computer Use 세션·커서·Simulator.app 창은 생성하지 않았다. 기존 다른 작업 소유 자원은 종료하지 않았다.
