# 신규 설정 뷰 — #158

2026-11-05 사용자 요청과 확정 답변을 반영한다. Figma 프로토타입 ver.2의 설정·학교 인증을 SwiftUI에 연결한다.

## 디자인 기준

[Figma 설정](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2835-2654)과 로그인 전 `4340:13157`, 학교 인증 `4266:11945`·`4266:12349`·`4266:12421`·`4266:12457`·`4314:12569`를 직접 조회했다.

- 기준 프레임 402×874pt. 상태바 62pt·홈 인디케이터 34pt를 포함한다. 앱은 시스템 safe area를 사용하고 시스템 바를 이미지로 그리지 않는다.
- 설정: 중앙 제목 Paperlogy Bold 30pt·갈색 `#754B00`, 좌우 20pt, 본문 시작 y146, 세로 섹션 간격 40pt. 제목 Medium 20pt, 카드 `#F3F3F3`·반경 15pt, 본인/학교 카드 테두리 `#CDCDCD` 1pt.
- 학교 인증: 제목 SemiBold 26pt, 좌우 20pt, 본문 y146, 필드 제목과 입력 간격 16pt·필드 사이 40pt. 입력 `#F7F7F7`·반경 30pt·최소 52pt. 선택 카드 `#F3F3F3`·반경 20pt·안쪽 20pt·간격 16pt·최소 78pt. 첨부 카드 최소 148pt와 내부 그림자, 하단 버튼 최소 57pt.
- 작은 375×667·기준 402×874·큰 440×956와 접근성 최대 글자 크기에서 스크롤·줄바꿈한다. 소셜 버튼은 기준 170pt 두 개와 20pt 간격, 작은 폭·큰 글자에서는 세로로 배치한다. 루트 화면 크기는 고정하지 않는다.

## 사용자 확정 사항

- Apple·Google은 기존 네이티브 스타일 버튼으로 대체한다. Apple은 AuthenticationServices 버튼과 기존 인증을 유지한다. 연결된 수단은 서버 `account_providers`만 사용하며 추정하지 않는다. 추가 연결은 기존 두 계정 재인증·미리보기·명시적 동의 흐름을 재사용한다.
- 본인인증과 회원 탈퇴는 버튼만 표시하고 비활성화한다. 실제 인증·삭제·성공 처리는 하지 않는다. 방법과 탈퇴 정책은 후속 결정이다.
- 농장 이름은 기존 닉네임 기반 `닉네임 + 의 밭`을 유지한다. 농장 카드의 수정은 기존 30자 닉네임 저장을 사용한다. 별도 6자 농장 이름 필드를 만들지 않는다.
- 권한은 실제 OS 상태를 표시하고 누르면 iPhone 설정으로 이동한다. 앱 내부에서 허용을 끄는 가짜 토글을 제공하지 않는다. 권한 행은 44pt 터치 영역을 유지한다.
- 학교 인증은 기존 분석·파일 처리 흐름을 재사용하며 Figma의 학교 정보→재학생/졸업생→자료 종류→첨부·명시적 요청 단계를 따른다. 학과는 검색 대신 직접 입력하고 건너뛰기를 지원한다. HWP는 사용자 결정으로 제외하며 JPEG·PNG·PDF 10MB를 유지한다.

## 저장·권한 경계

입학년도·학과는 공개 작성자 프로필 컬럼에 추가하지 않는다. `benchmark_private.oi_school_profile_metadata`와 인증된 대표 계정만 읽고 쓰는 RPC를 사용한다. 학교·입학년도·학과는 한 트랜잭션으로 저장한다. 학과는 앞뒤 공백을 정리하고 최대 100자, 건너뛰기는 명시적 null이다. 연도는 Gregorian 1900~현재 UTC 연도다.

기존 닉네임 변경은 학적정보를 보존한다. 학적정보는 학교와 함께 저장하고, 구버전에서 학교만 바뀌면 다른 학교의 학과·연도를 투영하지 않는다. 계정 통합은 기존 대표 프로필 유지 정책을 따른다. 공개 프로필·스토리 응답에 새 비공개 값을 합치지 않는다.

`school_profile_enabled` capability가 없는 서버는 기존 조회를 계속 사용한다. 새 저장만 준비되지 않았다는 오류를 표시한다. 새 migration `20261105082232_oi_school_profile_metadata.sql` 적용 전에는 학적정보 저장을 사용할 수 없다. 이 작업은 원격 migration이나 서버 배포를 수행하지 않는다.

첨부 파일 선택은 전송이 아니다. 파일을 읽은 뒤 OpenAI 전송 동의와 ‘인증 요청하기’를 모두 확인해야 기존 분석 API를 호출한다. 계정·요청 ID·취소를 검사하고 성공 후 원본 메모리는 해제한다. 기기 보호 저장소에는 요약·판정 시각만 저장한다. 결과는 공식 학교 소속·제출자 본인·문서 진위를 인증하지 않으며 작성 승인도 부여하지 않는다.

기존 외부 API `analyze-school-evidence`는 2026-11-05 읽기 확인에서 ACTIVE v4·JWT 검증 활성 상태였고, 배포된 네 소스가 기존 PR #140의 `c41c41bda9eb9073bd1fa61e5cc83d28defbea58`과 일치했다. 무인증 빈 POST는 401이었다. 서버 원본/재배포 소스는 해당 PR에 있으며 이번 PR은 중복 수입하지 않는다. 활성 환경 플래그와 실제 계정·문서 분석은 이 확인에 포함되지 않는다.

## 검증

검증 명령과 결과·캡처는 PR의 검증 절에서 확인한다. 실제 문서 대신 가상 URLProtocol 응답·가상 계정과 격리 PostgreSQL을 사용한다. 시각 검사는 실제 View를 4개 크기에 렌더하며, 생성한 창은 key window를 차지하지 않고 숨김 창까지 scene에서 분리됐는지 검사한다. 카메라·실제 provider 로그인·실제 문서 분석은 실기기 검증으로 남는다.

실행 결과: iOS Simulator 빌드·43개 테스트·29개 실제 화면 렌더 통과, Node 56개 통과, MY 도메인 검사와 격리 DB 검사 통과. 새 요약 DTO는 비격리 immutable Sendable 값으로 선언해 actor 저장소 경계를 명시했다. 기존 초안 모델의 Swift 5 동시성 경고와 AppIntents 메타데이터 경고는 별도 기존 범위로 남아 있다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug -destination 'platform=iOS Simulator,id=DA17B640-AC93-46C4-BF8B-9CBF7D5C1D7E' -derivedDataPath /private/tmp/benchmark-settings-158-build -resultBundlePath /private/tmp/benchmark-settings-158-reviewed.xcresult CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testMYSettingsCapturesWithOfflineAccounts -only-testing:OiDonationTests/OiRemoteStoreTests -only-testing:OiDonationTests/OiSchoolEvidenceContractTests test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/benchmark-settings-158-module-cache SWIFT_MODULECACHE_PATH=/private/tmp/benchmark-settings-158-module-cache sh apps/ios/Tests/run-my-checks.sh
python3 supabase/tests/run-account-merge-db-checks.py
(cd supabase && npm test)
git diff --check
```

[기준 설정](assets/settings-158/my-settings-signed-in-402x874.png), [로그인 전](assets/settings-158/my-settings-signed-out-auth-402x874.png), [학교 정보](assets/settings-158/school-evidence-profile-402x874.png), [인증 방식](assets/settings-158/school-evidence-affiliation-402x874.png), [재학생](assets/settings-158/school-evidence-student-document-402x874.png), [졸업생](assets/settings-158/school-evidence-graduate-document-402x874.png), [첨부](assets/settings-158/school-evidence-attachment-402x874.png), [작은 화면](assets/settings-158/school-evidence-profile-375x667.png), [최대 글자](assets/settings-158/school-evidence-profile-accessibility5.png)를 보관했다. 시스템 상태바는 offscreen View 캡처에 포함하지 않는다. 네이티브 글꼴의 행 높이와 사용자 지정 네이티브 소셜 버튼의 형태·상태 라벨에 따른 차이는 유지한다.

실행 리소스 최대 동시 그룹은 3개(전용 시뮬레이터, 빌드/테스트 실행기, 단일 캡처 창)였다. 캡처 창은 매번 숨김 상태까지 분리·해제 단언을 통과했고, 임시 PostgreSQL은 PID 파일·소켓 제거를 검사했다. 전용 시뮬레이터·앱·빌드 프로세스는 검증 뒤 종료했으며 사용자/다른 작업 리소스는 변경하지 않았다.
