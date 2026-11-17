# 작성자 공개 MY 검증

2026-11-17, develop 기준 커밋 7809bc4에서 iPhone 18 Pro iOS 27.0 시뮬레이터로 검증했다. 공개 프로필과 카드 캡처에는 가상 자료를 사용했다. 운영 Supabase에서는 공개 프로필과 작성자별 공개 이야기 조회가 HTTP 200을 반환하는지 읽기 전용으로 확인했다.

- 작성자 ID와 일치하는 공개 카드만 표시하고 비공개 카드, 다른 작성자 카드, 비공개 학적 정보를 제외한다.
- 공개 프로필의 농부 프리셋과 이름을 렌더링한다. 402×874, 375×667, 440×956 및 접근성 큰 글자 구성을 확인했다. 접근성 글자 크기에서는 기부자 탭의 장식 이미지를 숨겨 텍스트와 이동 버튼에 공간을 준다.
- 새 초안의 연결 대상 저장, 기존 초안 선택 보존, 본인 이야기와 계정 변경 시 선택 제외를 확인했다.
- 기존 이어진 이야기 RPC 테스트를 포함해 11개 통과, 실패·건너뜀·런타임 경고 0개. 실기기 및 운영 공개 등록 흐름은 확인하지 않았다.

~~~bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks \
  -destination 'id=AABEBE65-06A0-4CBA-AD42-5F7247F4AE99' \
  -derivedDataPath .qa-derived -resultBundlePath .qa-414-delivery.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:OiDonationTests/OiStoryContinuationTests \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testMapListCardAndSummaryCaptures \
  -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testCucumberStoryTabsOnCompactScreenAndLongPublicName \
  CODE_SIGNING_ALLOWED=NO
~~~

- [기부자 탭](donor-tab.png)
- [작성자 공개 MY](public-my.png)
- [작은 화면의 공개 MY](public-my-compact.png)
