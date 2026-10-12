# BenchMark Android Lo-fi

Kotlin + Jetpack Compose로 만든 화면·이동 확인용 앱입니다. Android Studio에서 이 디렉터리(`apps/android`)를 엽니다. 기존 웹의 빌드·배포와 독립되어 있습니다.

## 실행

- JDK 21, Android SDK Platform 36, Android Build Tools 35.0.0
- Gradle 8.14 / AGP 8.10.1 / Kotlin 및 Compose Compiler 2.1.20
- 최소 Android 8.0(API 26), target/compile API 36
- 로컬 확인용 application ID: `kr.ac.postech.benchmark.lofi` (배포용 식별자 아님)
- Android Studio의 **Gradle JDK**를 21로 지정합니다. 설치된 Studio의 bundled JDK 25는 이 Gradle 버전과 맞지 않습니다.
- SDK 위치는 Studio가 생성하는 `local.properties` 또는 `ANDROID_HOME`으로 지정합니다. 로컬 경로는 Git에 넣지 않습니다.

```bash
cd apps/android
./gradlew --no-daemon assembleDebug
./gradlew --no-daemon testDebugUnitTest lintDebug
```

Android Studio에서 `app`을 선택하고 기기 또는 에뮬레이터로 Run합니다. APK는 `app/build/outputs/apk/debug/app-debug.apk`에 생성됩니다.

## 범위

[Figma Lofi 504:1861](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH/BenchMark?node-id=504-1861)의 화면 구성과 흐름을 구현했습니다. 디자인 고도화 요청이 아니므로 기본 Material 컴포넌트와 회색 이미지·지도 영역을 사용합니다. 원본 iPhone 시스템 바 및 iOS 권한 팝업은 Android에 복제하지 않습니다.

- 로그인 예시 → 기부자 정보 입력 여부 → 입력/본인인증 예시 → 홈
- 홈 → 벤치 위치 → 벤치 선택 → 기부 안내 → 약관 → 인증 예시 → 금액 → 인적사항 → 스토리/이미지 → 접수 예시
- 나의 기부 → 빈 상태 또는 예시 내역 → 상세 → 편집/미리보기 → 진행 사항 → 설치 결과
- NFC 예시 → 기부자의 이야기 → AR 화면 → 권한 허용/거부 예시 → 촬영/저장 결과 예시
- 홈·나의 기부·벤치·AR 체험 탭, 프로필, 알림 빈 화면

실제 로그인, 본인인증, 결제, API, 데이터베이스, 지도 SDK, NFC, AR, 카메라, 사진 보관함, 위치 서비스는 연결하지 않습니다. 앱은 네트워크·기기 권한을 선언하지 않습니다. 최소금액 100만원과 3년 기한은 lo-fi의 문구를 재현한 예시이며 실제 운영 정책 확정이 아닙니다. 로그인 입력은 예시이며 인증에 사용하거나 전송하지 않습니다. SNS 제공자 이름은 원본에 없어 SNS 1~3으로 표시합니다.

## 화면 대응

| Figma node | 화면 |
| --- | --- |
| 504:2166, 504:2176 | 로그인, 정보 입력 여부 |
| 510:2193, 510:2194 | 기부자 정보, 인증 |
| 505:524, 505:531 | 홈 변형을 한 홈 화면으로 통합 |
| 514:2370, 514:2336 | 벤치 목록/위치, 선택 |
| 514:2362, 514:2401 | 기부 설명, 약관/인증 |
| 514:2400, 515:2424 | 기부금, 인적사항 |
| 515:2481, 515:2497 | 스토리 작성, 접수 |
| 513:717, 513:773, 515:2502, 515:2501 | 기부 빈 상태/내역/편집/설치 결과 |
| 510:2306, 510:2316, 510:2329 | NFC, 이야기, AR |

사진 선택·접수 내용 확인·진행 단계·촬영 결과는 원본 흐름도에 있고 상세 프레임이 없는 화면입니다. 기본 컨트롤로 흐름만 보완했습니다. 프로필은 기존 기부자 입력 화면을 재사용하며 알림은 빈 상태입니다. 진행 단계 이름은 6단계 도형을 설명하기 위한 예시입니다.

## 상태와 내비게이션

- `BenchmarkApp.kt`: 단일 `NavHost`, 화면 연결, 탭과 뒤로가기
- `LofiState.kt`: `SavedStateHandle`을 사용하는 화면 예시 상태
- `DonationScreens.kt`: 기부 및 내역 화면
- `ExperienceScreens.kt`: 로그인/인증/NFC 이후 AR 화면
- `Components.kt`: 공통 입력/스크롤/회색 영역

입력값은 뒤로가기와 Activity 재생성에서 유지됩니다. 편집본과 저장본을 분리하여 취소 시 원본을 보존합니다. 접수 후 입력 단계는 백스택에서 제거합니다. 탭 이동은 홈을 기준으로 정리해 중복 누적을 막습니다. 예시 상태는 서버나 영구 저장소에 저장하지 않으며 프로필의 초기화 버튼으로 제거할 수 있습니다. 주민등록번호 입력은 비활성 영역만 표시합니다.

402×874 원본의 정보 순서를 유지하되 고정 화면 크기를 강제하지 않습니다. 시스템 영역과 키보드 inset을 처리하고 내용은 스크롤됩니다. 원본에 없는 세밀한 스타일은 기본값을 사용합니다.

## 자동 검증

`NavigationTest`는 Robolectric API 35 환경에서 실제 Compose 화면을 클릭합니다. 온보딩 건너뛰기/입력, 금액·약관 조건, 사진 선택/거부, 접수 백스택, 편집 취소/저장, Activity 재생성, 탭 반복, AR 권한 재시도, 320dp 화면의 이동을 검증합니다.

테스트 화면 캡처는 `app/build/lofi-screenshots/`에 생성합니다. 이는 기기나 에뮬레이터 캡처가 아닌 Robolectric의 화면 렌더링입니다. 실기기의 키보드, 시스템 뒤로가기 제스처 및 접근성 서비스 확인은 별도입니다.

버전 호환 근거: [AGP 8.10](https://developer.android.com/build/releases/agp-8-10-0-release-notes), [Kotlin Compose Compiler 설정](https://kotlinlang.org/docs/compose-compiler-migration-guide.html).

## 이번 구현 검증 결과

2026-09-30, macOS arm64 / Microsoft OpenJDK 21.0.7에서 실행했습니다.

```bash
JAVA_HOME='/Users/don/Library/Java/JavaVirtualMachines/ms-21.0.7/Contents/Home' ANDROID_HOME='/Users/don/Library/Android/sdk' ./gradlew --no-daemon assembleDebug testDebugUnitTest lintDebug
```

- 최종 실행: 성공, 테스트 6개 통과, 실패/스킵 0
- lint: 오류 0, 경고 8 (라이브러리/Gradle 최신 버전 안내 6, 백업 규칙 권고 1, 앱 아이콘 미지정 1)
- 화면: 402×874와 320×640 오프스크린 렌더링 확인
- 실기기/에뮬레이터 실행, 실제 키보드 및 시스템 제스처: 미검증
- 첫 캡처 API의 Robolectric 타임아웃은 View/Canvas 렌더링으로 수정했고, API 27 전용 스타일 속성은 제거해 최소 API 26 선언에 맞췄습니다.

| 홈 | 기부 상세 | 작은 화면 |
| --- | --- | --- |
| ![홈](../../docs/android-lofi/home.png) | ![상세](../../docs/android-lofi/donation.png) | ![작은 화면](../../docs/android-lofi/small-screen.png) |

이미지는 Robolectric 테스트 캡처이며 실제 기기 캡처가 아닙니다.
