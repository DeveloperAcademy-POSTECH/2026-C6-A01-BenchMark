# NFC → App Clip 기본 진입

2026-10-22 / #89 후속 요청

## 현재 연결

- 전체 앱: `com.Spero.OiDonation`
- App Clip: `com.Spero.OiDonation.Clip`
- 기본 NFC 주소: `https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip`
- `Domain/Routing/AppClipLink.swift`가 NFC 화면·Clip·본 앱의 공통 주소와 검증을 소유한다. Clip 타깃의 공유 소스 목록에도 포함한다.
- HTTPS, Apple 호스트, `/id`, 단일 `p`의 정확한 Clip ID를 검증한다. 자격증명, 다른 포트·앱 ID·호스트·경로, 중복 `p`, fragment는 거부한다. 추가 캠페인 쿼리는 허용하지만 명패 ID로 해석하지 않는다.
- 명패 ID 없는 기본 링크는 Clip의 서비스 안내 화면을 표시한다. 명패별 콘텐츠·AR을 구현했다고 표시하지 않는다. 실행 앱에 `example.com`이나 테스트 이야기 저장소를 연결하지 않는다. 승인된 웹 도메인·이야기 API 연결은 별도 작업이다.
- `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`와 `onOpenURL`을 처리한다. 호출마다 SwiftUI `.task(id:)`를 갱신하며 새 호출·취소 이후의 오래된 조회 결과는 버린다.
- 전체 앱이 이미 설치된 경우 같은 URL을 받으면 홈으로 이동한다. 다른 도메인에 대한 기존 라우팅은 유지한다.
- `OiDonationClip` 공유 스킴의 Run에 `_XCAppClipURL`을 설정했다. Xcode에서 이 스킴으로 실행하면 기본 URL 처리 코드를 시험할 수 있다. 이 실행만으로 NFC 카드나 공개 배포를 검증한 것은 아니다.

## 원격 상태 — 2026-10-22 확인

App Store Connect의 오이기부 앱 ID는 `6823676043`이다. 버전 1.0은 제출 준비 중이며 기본 경험의 헤더·부제목·작업, 기본 링크·데모 URL이 비어 있다. 현재 로그인 계정에서는 해당 편집 UI가 비활성 상태다. TestFlight에는 2026-10-17 업로드한 내부 빌드 `1.0 (1)`이 있으며 벤치마크 그룹에서 테스트 중이다. 등록된 테스트 호출 제목·URL은 없다. 기존 빌드에는 이번 수정이 없다.

사용자가 관리자에게 원격 작업을 전달하기로 했으므로 이 작업에서 계정 권한 변경, 원격 경험 등록, 새 빌드 업로드, 심사 제출은 수행하지 않았다. 현재 Mac의 유효한 서명 신원은 Apple Development이며, 배포 인증서와 배포용 프로필은 별도 준비가 필요하다.

## 관리자에게 전달할 작업

권한을 변경할 필요 없이 관리자가 본인 계정에서 진행한다.

1. `feat/#89-nfc-writer`의 최신 코드를 확인하고, `OiDonation` 스킴으로 App Clip을 포함한 Release 빌드를 아카이브한다. 기존 빌드 1과 구분해 두 타깃의 빌드 번호를 2 이상으로 맞춘다. 개발용 프로필을 배포용 프로필로 오인하지 않는다.
2. 배포 담당자의 Apple Distribution 서명과 App Store Connect 배포 경로로 검증·업로드한다. 개발용으로 서명한 로컬 아카이브는 Organizer에서 배포 서명으로 다시 내보내야 하며, 그 자체가 업로드 가능한 IPA는 아니다. 개인 키·인증서·프로필을 Git이나 채팅에 올리지 않는다.
3. App Store Connect → 오이기부 → 배포 → iOS 버전 → 앱 클립에서 아래 항목을 등록한다.
   - 헤더: 팀에서 사용할 이미지, PNG/JPEG, 1800×1200, 3:2.
   - 부제목 제안: `벤치에 남은 이야기를 만나보세요`.
   - 작업: `열기`.
4. 처리된 새 빌드를 해당 버전에 선택하고 기본 경험을 저장한다. 생성된 기본 링크의 `p`가 `com.Spero.OiDonation.Clip`인지 확인한다.
5. 공개 배포는 앱의 나머지 필수 메타데이터와 심사 요건도 충족한 뒤 진행한다. 기본 링크와 데모 URL은 버전 승인 후 활성화된다. 현재 Clip은 서비스 안내 진입까지만 구현되어 있으므로 공개 심사에 필요한 기능 완성도는 배포 담당자가 별도 검토한다.

TestFlight의 App Clip 시험도 관리자가 새 빌드 → 테스트 정보 → 앱 클립 호출에 제목 `오이기부`, 위 기본 URL을 추가하고 저장해야 한다. TestFlight 시험은 TestFlight 앱의 호출로 확인하며, 이것만으로 일반 NFC 호출이 활성화된다고 간주하지 않는다.

## 개발 기기에서 실물 NFC 시험

공개 승인 전에도 Xcode 설치와 로컬 경험으로 개발 기기의 NFC 진입을 시험할 수 있다. 실제 NFC 태그·카드 노출은 시뮬레이터로 검증할 수 없다.

1. Xcode에서 `OiDonationClip` 스킴과 등록된 실제 iPhone을 선택해 실행한다. 기본 링크를 받은 뒤 서비스 안내 화면이 표시되는지 확인한다.
2. 해당 iPhone에서 설정 → 개발자 → 로컬 경험 → 로컬 경험 등록으로 들어간다. URL 접두사에 위 기본 NFC 주소, 번들 ID에 `com.Spero.OiDonation.Clip`, 제목·부제목·이미지를 넣는다. 이 설정은 해당 개발 기기에만 적용된다.
3. NFC 기록 화면에서 위 주소를 쓰기 가능한 태그에 기록하고 재읽기 성공을 확인한다.
4. 전체 앱이 없는 별도 시험 iPhone에 로컬 경험을 등록해 NFC를 인식한다. 알림·App Clip 카드에서 열기를 선택하고 안내 화면을 확인한다. 사용자의 기존 앱이나 데이터를 자동 삭제하지 않는다.
5. 잘못된 Clip ID, 같은 태그 재인식, 앱 클립을 메모리에 둔 상태의 재호출, 네트워크가 없는 상황을 각각 확인한다. 기본 안내 화면은 네트워크 조회를 하지 않는다.

실기기의 로컬 경험 등록·NFC 카드·공개 서버 해석은 아직 확인하지 않았다. 사용자/관리자 시험 결과와 공개 승인 상태를 코드 빌드 성공으로 대체하지 않는다.

## 검증

현재 도구는 Xcode 27.0이며 배포 대상은 본 앱 iOS 26.2·App Clip iOS 27.0, Swift 언어 모드는 5.0이다. 이번 작업에서 변경하지 않았다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/benchmark-nfc89-module-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/benchmark-nfc89-module-cache \
sh apps/ios/Tests/run-app-clip-checks.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiDonation \
-sdk iphoneos -configuration Debug -destination 'generic/platform=iOS' \
-derivedDataPath /private/tmp/benchmark-nfc89-signed-build build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiDonation \
-configuration Release -destination 'generic/platform=iOS' \
-derivedDataPath /private/tmp/benchmark-nfc89-signed-build \
-archivePath /private/tmp/benchmark-nfc89-invocation/OiDonation-1.0-2.xcarchive \
CURRENT_PROJECT_VERSION=2 archive
```

자동 검증은 정상 링크 5개·거부 링크 20개, 기본 진입, 본 앱 홈 이동, nil·오류 후 재진입, 이야기 조회 성공·없음·오류, 취소·오래된 응답을 확인한다. 개발용 서명 빌드와 Release 아카이브, 아카이브의 두 번들 ID·빌드 번호 2·코드 서명도 확인한다. 이 아카이브에는 로컬 개발용 서명이 포함되므로 저장소에 추가하지 않는다.

## 화면 검증

실제 SwiftUI 화면을 320·393·440pt, 접근성 글자 크기, 다크 모드로 6종 렌더링했다. 아래는 393pt 결과이며 실물 NFC 카드 화면이 아니다.

![App Clip 기본 진입](../../../docs/screenshots/nfc-writer/app-clip-welcome.png)

## Apple 공식 근거

- [기본 경험·기본 링크·이미지 규격과 승인 시점](https://developer.apple.com/help/app-store-connect/offer-app-clip-experiences/offer-a-default-app-clip-experience/)
- [호출 URL 수신](https://developer.apple.com/documentation/appclip/responding-to-invocations)
- [Xcode 호출 디버깅·로컬 경험·실물 NFC 시험](https://developer.apple.com/documentation/appclip/testing-the-launch-experience-of-your-app-clip)
- [TestFlight App Clip 호출 설정](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-an-app-clip-experience/)
