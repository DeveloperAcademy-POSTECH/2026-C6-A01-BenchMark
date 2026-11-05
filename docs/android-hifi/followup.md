# Android 온보딩·내 기부·후원 hi-fi

## 적용 범위

2026-10-12, #67 작업 브랜치에서 Figma 프로토타입 `795:1610`의 온보딩·내 기부·후원 화면을 이어 구현한다. 기본 글꼴은 사용자 승인대로 Android 기본 글꼴을 유지한다. 참조 크기는 402×874이며 Android에서는 논리 단위를 dp/sp로 적용하고 루트 크기는 고정하지 않는다.

| Figma node | Android 구현 |
| --- | --- |
| 820:1830 | O/X 선택·다음·선택 복원 |
| 1173:928 / 1239:1379 | 단일/2열 카드, 최신/오래된/좋아요 정렬, 뒤집기·로컬 반응·상세/편집/미리보기 |
| 1450:6836 / 1386:5201 | 후원 소개와 5단계 안내 |
| 1386:5314 | 4개 약관 예시와 선택 상태 |
| 1399:5544 | 금액 입력·증액·예정일·학교 결제 방법 안내 |
| 1423:6019 / 1423:6240 | 기부자 구분·이야기 작성자 이름·학교 개인정보 입력 안내 |
| 1450:6556 / 1450:6769 | 제목/내용·사진 미리보기·신청 내용 예시 확인 |

## 공개 홈과 선택 로그인

Figma Plugin API로 읽은 프로토타입 연결은 `958:4279 → 979:4333 → 1021:4493`이다. 이 진입 경로에 로그인 화면은 없다. Android는 대기 애니메이션을 두지 않고 비로그인 공개 홈으로 바로 진입한다. #45의 로그인 강제 진입 조건을 홈 앞에 유지했던 판단은 이번 변경에서 수정했다.

- 홈·벤치 탐색·후원 소개·공개 이야기·AR 진입은 비로그인 상태에서 열 수 있다.
- 내 기부·프로필·계정 알림·신청 입력 단계는 계정 기능을 선택했을 때 로그인한다.
- OAuth 설정이 없거나 세션을 확인하지 못해도 공개 홈은 차단하지 않는다.
- 로그인 후 온보딩을 마치면 요청한 계정 화면으로 돌아간다. 비로그인 탐색에서 고른 벤치도 유지한다.
- 게스트와 계정별 ViewModel을 구분한다. 로그아웃 시 계정 초안은 초기화하고 공개 홈으로 돌아간다.
- Google PKCE·콜백 검증·Keystore 저장은 기존 구현을 유지한다. 테스트 인증 서비스는 src/test에만 있다.

## 원본과의 차이 및 제품 경계

- 직접 결제·학교 본인인증·약관 처리·서버 신청은 연결하지 않는다. 실제 약정·납입·영수증은 학교의 공식 절차에서 처리한다.
- Figma의 5만원은 디자인 입력 조건이며 운영 최소 기부금을 확정한 것이 아니다. 선택한 금액·예정일은 로컬 예시다.
- 주민등록번호·학교 연락처·학적 정보를 신규 폼에서 입력하지 않는다. 해당 위치에는 학교 공식 절차 안내를 표시한다. 프로필은 기존 로컬 예시 입력을 유지한다.
- `기부 완료`를 실제 납입 완료로 표시하지 않는다. 로컬 신청 예시 확인 및 학교 확인 대기로 구분한다.
- 사진 없이도 신청 예시를 확인할 수 있다. 실제 사진 보관함 대신 Figma 원본 디자인 사진을 명시적으로 선택한다.
- 카드 날짜·사진·반응은 로컬 예시이며 학교 기록·운영 데이터가 아니다. 사례는 `기부 내역 예시 불러오기`를 누를 때만 생성한다.
- iPhone 시스템 UI·SF Symbols·Apple Wallet은 복제하지 않는다. Android 아이콘·탭과 별도 AR 버튼을 사용한다. Apple Wallet 연동은 범위 밖이다.
- [Compose blur 공식 문서](https://developer.android.com/develop/ui/compose/graphics/images/customize)에 따라 Android 12 이전에는 배경 블러가 적용되지 않는다. 최소 API 26의 입력·이동은 별도로 검증한다.
- 글꼴·일부 날짜/문구·안내 밀도·지도 예시와 네이티브 컨트롤은 원본과 차이가 있다. 픽셀 단위 동일성이나 실서비스 완성을 주장하지 않는다.

## 적응형 배치와 검증

402dp에서는 정렬·보기 전환을 한 줄에 배치하고 320dp에서는 필요한 만큼 줄바꿈한다. 그리드는 2열을 유지하고 카드 폭·이미지 슬롯은 가용 폭에 비례한다. 폼은 좌측 단계 라인·34dp 본문 들여쓰기를 유지하고 작은 화면·키보드에서는 스크롤된다. 제목은 30, 내용은 500 Unicode code point로 제한하며 emoji의 surrogate pair를 잘라내지 않는다. Compose Preview에는 320/402/600dp와 1.5배 글자 크기를 포함한다.

```bash
JAVA_HOME='/Users/don/Library/Java/JavaVirtualMachines/ms-21.0.7/Contents/Home' ANDROID_HOME='/Users/don/Library/Android/sdk' apps/android/gradlew -p apps/android --no-daemon assembleDebug testDebugUnitTest lintDebug
cd apps/android
python3 tools/check_ar_models.py
```

최종 검증 결과: 빌드 성공, 테스트 41개 통과(실패·오류·건너뛰기 0), lint 오류 0·경고 23, AR 모델 5개 검증 통과.

Robolectric API 35의 온보딩·빈/단일/그리드/지도·후원 전 단계 42개 캡처를 320/402/600dp에서 확인한다. API 26의 320dp 이동도 검증한다. 캡처는 실제 기기 사진이 아니다. 실제 기기·TalkBack·실제 Google 로그인/앱 복귀·학교 연동은 미검증이다.

## 실행 위치

- `/Users/don/BenchMark/apps/android`: develop, 사용자 요청으로 #43·#45·#65를 병합한 통합본. 이 후속 PR이 병합되기 전에는 공개 홈 수정과 새 화면이 포함되지 않는다.
- `/Users/don/.codex/worktrees/android-hifi-flow/BenchMark/apps/android`: 이 작업의 최신 화면·공개 홈 수정본. Android Studio에서 이 폴더를 별도로 열면 확인할 수 있다.
- Android Studio의 Gradle JDK는 21을 사용하고 Sync 완료 후 app 모듈과 기기를 선택한다. `Module: <no module>`이면 Run하지 않는다. Allow multiple instances는 해제한다.

대표 캡처: [비로그인 홈](flow/guest-home-402.png), [온보딩](flow/onboarding-402.png), [내 기부](flow/donations-grid-402.png), [320dp 지도 카드](flow/donations-map-320.png), [후원 금액](flow/support-amount-402.png). 전체 캡처는 CI의 `android-lofi-verification` 아티팩트에 포함한다.
