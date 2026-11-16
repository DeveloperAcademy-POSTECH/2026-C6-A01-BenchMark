# 앱 전역 fail-safe 점검 — 2026-11-03

관련 이슈: #123, #124. 기준은 `develop`의 실제 실행 경로다. 코드·장애 주입·컴파일·실기기 증거를 구분한다. 실제 사용자의 세션·증빙·기록을 개발 검증을 위해 변경하지 않는다.

## 확인한 결함과 보완

| 경로 | 실제 실패 | 보완 및 회귀 검사 |
| --- | --- | --- |
| 로그인 재진입 | 작업 진행 중 재진입을 설정 누락으로 표시 | busy와 API 존재를 분리, 실제 Store 검사 |
| 로그인 취소 | 정상 브라우저 취소가 전역 연결 경고로 남음 | CancellationError 정규화, 현재 세션 보존 |
| 화면 비활성화 | URLSession의 취소를 일반 연결 오류로 표시 | Foundation·URLSession 취소 공통 판별 |
| 인증 Task 취소 | continuation·진행 상태가 callback까지 남음 | 시도별 단일 종료, 브라우저 취소·핸들 해제, 늦은 성공 거절 |
| 오류 재시도 | 성공 재조회 뒤 오래된 오류가 계속 남음 | 오류 revision으로 이전 오류만 해제, 새 저장 오류 보존 |
| 기기 초안 | 손상 JSON 하나가 전체 목록을 막음 | 손상 파일별 격리·경고·원본 보존, 실제 I/O 실패는 표시 |
| 편집기 복원 | 복원 실패 뒤 편집·저장·정상 나가기 막힘 | 복원 재시도와 원본을 덮어쓰지 않는 나가기 |
| 녹화 export | 변환 실패·백그라운드 취소에도 정상 raw 원본 삭제 | 앱 전용 영구 보관, 정상 export 뒤만 삭제, 명시적 원본 저장·공유·삭제 |
| 앱 계정 통합 | Auth ID와 앱 소유자를 같게 취급하면 기존 사진·승인 조회 실패 | canonical ID 분리, 원래 Storage 소유자 보존, 기기 초안 충돌 경고·원본 보존 |

## 점검한 영역

인증·키체인 저장·세션 갱신·로그아웃·계정 전환, 공개·개인 데이터 조회와 저장, 증빙 중단 재시도, 이야기·사진·초안 보관, AR 카메라의 진입·복귀·권한·중단, 영상 내보내기, NFC 요청 검증, App Clip 진입·수집 모델을 확인했다. 기존 정책을 임의로 변경하거나 미정 수집 조건을 새로 정하지 않는다.

기존 AR lifecycle 검사는 fake recorder를 사용해 원본 삭제 결함을 잡지 못했다. 신규 영상 검사는 실제 파일 보존 helper와 실패·취소·store 재생성을 검사한다. App Clip의 기본 승인 host와 실제 콘텐츠 제공 여부는 별도 배포 설정이며, 비활성 경로의 코드 검사를 현장 수집 검증으로 표시하지 않는다.

## 검증 명령

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-oi-service-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-ar-recovery-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-ar-camera-lifecycle-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-app-clip-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-draft-recovery-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-draft-adoption-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-ar-video-recovery-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-apple-exchange-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-account-connection-flow-checks.sh
npm --prefix supabase test
python3 supabase/tests/run-account-merge-db-checks.py
```

Store 회귀는 `OiFlowChecks`의 `OiRemoteStoreTests`로 검증했다. Simulator XCTest 25개가 실패·건너뜀 없이 통과했고, Node Edge 검사 56개와 격리 PostgreSQL 18 DB 검사도 통과했다. Xcode 27.1·iOS 27.0 Simulator를 사용했으며 프로젝트의 Swift 언어 모드와 배포 대상을 바꾸지 않았다.

실행한 전체 앱·App Clip·테스트 호스트 빌드 및 XCTest 명령은 다음과 같다. 검증 전용 Simulator는 검증 후 삭제했다. 실제 provider 인증과 서명된 기기 실행의 증거는 아니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug \
  -destination 'platform=iOS Simulator,id=3D1BAE24-6DF4-42B8-8831-909FE85E0E47' \
  -derivedDataPath /private/tmp/benchmark-failsafe-123-qa/build \
  -resultBundlePath /private/tmp/benchmark-failsafe-123-qa/final-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 test
```

최신 `develop`의 App Clip AR 변경(`d028406`)을 통합한 뒤 `OiFlowChecks build-for-testing` 전체 빌드와 App Clip·AR 복구·카메라 lifecycle 검사를 다시 통과했다. 위 XCTest 25개는 통합 전 동일한 인증·계정 소스에서 실행한 결과다.

로컬 Deno 실행 파일은 없어 Edge Deno 타입 검사는 수행하지 못했다. CI의 `npm --prefix supabase run check`와 PostgreSQL 16 검사를 별도로 확인한다.

## 계정 화면 캡처

실제 Store에 테스트용 API·기기 저장소만 주입한 XCTest 호스트에서 375·402·440pt 폭을 렌더링했다. 실제 사용자 계정·증빙은 캡처하지 않았다. 아래는 402pt 기준이며 전체 폭별 이미지는 [검증 폴더](verification/failsafe-20261103)에 있다. 시스템 Apple 버튼의 언어는 Simulator의 시스템 언어를 따른다.

![MY 계정 진입](verification/failsafe-20261103/account-connection-account-402.png)
![로그인 방법 추가](verification/failsafe-20261103/account-connection-add-method-402.png)
![기존 계정 통합](verification/failsafe-20261103/account-connection-merge-existing-402.png)

## 실기기 검증과의 경계

Needs confirmation:
- Apple Developer capability·갱신된 프로파일·Supabase Apple provider의 실제 설정과 계정 인증.
- ReplayKit이 정상 raw를 생성한 뒤의 백그라운드 만료·저장 공간 부족·복구 원본 재생. 파일 생성 전에 OS가 강제 종료한 녹화까지 복구된다고 보장하지 않는다.
- 실제 카메라·마이크·사진 보관함·NFC·AR의 현장 동작.

자동 검사가 통과해도 위 항목을 완료로 처리하지 않는다. 실제 계정 통합은 양쪽 재인증·미리보기·명시적 동의를 거친 경우에만 실행한다.

## 2026-11-04 제품 경로 재점검

제품 정리 브랜치와 Draft PR #142를 기준으로 iOS 본 앱과 App Clip의 실패·재시도·중단 경로를 점검했다. 호출 누락과 콘텐츠 0건 화면은 [제품 경로 기록](product-app-cleanup.md)과 [빈 화면 목록](empty-state-inventory.md)에서 관리한다.

| 경로 | 확인한 실패와 보완 |
| --- | --- |
| 설정·인증 | 로그아웃을 현재 세션으로 제한하고 서버 세션 정리 실패를 재조회 뒤에도 표시한다. 닉네임·학교는 바꾼 필드만 전송해 다른 기기의 수정을 보존한다. |
| 이야기 편집·사진 | 서버 버전 교체 전에 대상 필드를 안내하고 사용자가 확인한 교체본을 기기에 저장한 뒤 화면을 바꾼다. 업로드 응답을 잃은 사진도 삭제 기록에 남겨 다시 나타나거나 함께 제출되지 않게 하고, 서버의 최신 첨부 목록에서 지정 사진만 뺀다. 서명 URL과 사진 다운로드는 같은 화면에서 다시 시도할 수 있다. |
| 기기 초안 삭제 | 명시적으로 삭제한 초안은 먼저 목록에서 분리한다. 사진 정리가 중단되면 일부 사진만 지워진 초안을 다시 열거나 자동 저장하는 대신 정리를 재시도할 수 있다. |
| 옷장 사진 | 현재 사진 배치를 보존한 채 3D 모델과 사진 미리보기를 다시 만들 수 있다. 백그라운드 전 작업의 늦은 완료가 현재 미리보기 상태를 바꾸지 않게 한다. |
| 카드 요청 | 통신이 끊기면 원래 수락·거절을 재전송해 처리 결과를 확인한다. 대기 목록에서 빠진 요청도 같은 결정의 서버 영수증을 다시 받을 수 있다. |
| 지도·현장 AR | 잘못된 좌표 배열은 앱을 종료시키는 대신 지도 오류로 처리한다. AR 화면 아래의 지도 렌더러를 해제하고, 이전 AR 조회가 취소된 뒤 최신 세션을 중단하지 않게 한다. |
| MY·App Clip 도감 | 가져온 카드를 진행 중이던 조회가 다시 표시하지 않게 한다. 인증이 바뀌거나 기기 기록을 읽지 못하면 원본을 보존하고, App Clip 카드 결과에서는 삭제 없이 나갈 수 있다. |

Xcode 27.1과 iOS 26.5 iPhone 17 시뮬레이터에서 `OiFlowChecks` 47개가 통과했다. 지도·위치, AR 복구·카메라 생명주기, 초안, App Clip 도감, API·인증 보조 검사도 통과했다. 잠긴 사진 파일로 기기 초안의 부분 삭제를 재현하고 목록 재진입 시 정리가 끝나는지 검증했다. [카드 요청 재확인 화면](verification/product-141/card-requests-unconfirmed-decision-402x874.png)

Needs confirmation:

- 실제 iPhone의 인증 공급자 복귀와 현장 AR 카메라·GPS 권한 변경, 백그라운드 전환 및 재진입.
- 서명된 App Clip과 본 앱 사이의 App Group 저장과 가져오기. 카드 요청의 실제 두 계정 수락·거절과 응답 유실 재시도.

## 2026-11-11 출시 브랜치 재점검 — #287

최신 `main`의 `aa41997`에서 iOS의 지도와 원격 동기화 수명, Supabase 수집 집계 쿼리를 점검했다. 공개 이야기와 계정 상태의 30초 동기화를 유지하고, 갱신이 같은 공개 참조 데이터와 화면 모델의 반복 작업을 줄였다. 수집 집계 오류가 발생해도 정상 응답을 받은 이야기 상태를 적용한다.

- PostgreSQL 18.4의 합성 공개 이야기 5,000건과 수집 50,000건으로 전체 집계를 3회 비교했다. 서버 실행 시간 중앙값은 기존 페이지 집계 151.32ms, ID 일괄 집계 15.85ms였다. 운영 DB 17.6에서 읽기 전용으로 확인한 규모는 공개 이야기 2건과 수집 1건이다. 신규 RPC는 마이그레이션으로 제공한다.
- 최초 `OiFlowChecks` 전체 실행은 156개 통과, 2개 실패, 수동 조작 3개 건너뜀이었다. 오이 초상 이미지 교체 시 투영을 다시 요청하도록 보완했다. 변경 전 `main`의 마커·붙여넣기 검사 2개와 보완 후 변경 범위 검사 13개가 통과했다. 여러 줄 붙여넣기의 최초 실패는 재현되지 않았다.
- 독립 iOS 검사 22개, App Clip 폰트·AR 이미지, 콜라주, iPhone용 미서명 Release 빌드, Supabase Node 검사 42개와 격리 DB 회귀 검사를 통과했다. 새 집계는 공개·숨김·초안·0건·중복 ID·최대 200개 입력과 기존 RPC 호환을 검증했다.
- 운영 DB Performance Advisor에서 인덱스가 없는 외래 키 9건, 사용 기록이 없는 인덱스 5건, 같은 역할·동작에 적용되는 허용형 RLS 정책 중복 2건을 확인했다. 출시 DB의 데이터 규모와 조회 통계를 고려해 집계 경로에 필요한 기존 인덱스를 사용했다.
- Xcode 27.1에서 Swift 6 전환 시 오류가 될 격리 진단과 사용 중단 API 경고가 남는다. 보완 후 `testPanEdgesBounceAndRebaseDuringMultitouch`에서 우선순위 역전 런타임 경고가 1건 기록됐다. 실기기의 홈 지도 유휴 전력·열 상태와 현장 GPS·AR 카메라, 실제 제공자 로그인은 별도 확인이 필요하다.


## 2026-11-14 develop → main 통합 점검 — #329

NFC 연동 후 독립 Swift 검사에서 `StoryRepository`의 `AppClipLink`, `OiServiceAPI`의 `OiNFCTagError` 참조를 컴파일할 입력이 누락되어 있었다. 구조·MY·AR 시각 검사에 `AppClipLink.swift`, Apple 인증 교환·서비스 검사에 이 파일과 `OiOperatorNFCTagModel.swift`를 추가했다. 앱 런타임 동작이나 개인 서명 설정은 바꾸지 않았다.

보완 후 구조·Apple 인증 교환·MY·서비스 검사 4개가 통과했고 AR 시각 검사 실행 파일도 같은 입력으로 독립 컴파일했다. App Clip 링크·캠퍼스·NFC 검사 3개도 통과했다. iOS 27.2에서 지도/교육지구·원격 저장/운영자·양면 카드/사진/오이 편집 검사 126개 통과, 명시적 수동 조작 3개 건너뜀, 실패 0건이다. 본 앱과 App Clip의 미서명 Release 빌드 및 임시 로컬 PostgreSQL 전체 마이그레이션·권한 회귀 검사가 통과했다. 교육지구 웹 체험 검사 중 우선순위 역전 경고 1건은 남는다.
