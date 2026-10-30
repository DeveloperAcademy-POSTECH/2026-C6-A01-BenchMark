# Supabase 전체 플로우 연동 — #100

## 확정 범위 — 2026-10-28

- 기존 `52gibu` 프로젝트(`kfzfzarslqdqmrazohej`)를 사용한다. 새 프로젝트는 만들지 않는다.
- DB 마이그레이션, RLS, Storage, API, iOS 연동과 원격 동작 검증까지 작업한다. 백업은 사용자의 요청에 따라 생략한다.
- 운영자의 기부 증빙 검토와 글 작성 승인을 적용한다. 학교 공식 납입 확인·영수증 발급을 대신하지 않는다.
- 피클코인은 비활성화한다. 기부금 환산·구매·적립·차감 정책은 구현하지 않는다.
- 백업 생략을 무관한 데이터·Auth 계정·Storage 전체 삭제 승인으로 해석하지 않는다.
- 기존 돗자리 웹, Sites 이전, 사용자의 개인 서명과 미추적 작업은 보존한다.

## 현재 확인 결과

- `apps/android/README.md`와 `apps/android/app/build.gradle.kts`에 프로젝트 URL과 ref가 일치한다. 공개 키는 Git에서 제외된 로컬 설정으로 주입하고 있다.
- 2026-10-28 일시 정지된 프로젝트를 사용자가 재개하고 BenchMark 조직에 OAuth를 재승인했다. 이후 MCP에서 `ACTIVE_HEALTHY`, PostgreSQL 17.6을 확인했다. 다른 조직·프로젝트는 변경하지 않았다.
- 잘못 서명된 Supabase CLI 2.107.0은 공식 Homebrew 재설치로 2.122.0으로 복구했다. 서명 검사를 우회하지 않았다.
- 아래 네 마이그레이션은 기존 원격 프로젝트에 적용됐다. 기존 Auth 사용자 2명과 기존 `public.users`를 보존했다. 사용자가 지정한 기존 계정 1명에만 비공개 운영자 권한을 부여했다. 개인 이메일·사용자 ID는 마이그레이션에 넣지 않았다.
- iOS의 기본 실행은 원격 데이터를 사용한다. 예시 데이터는 preview에서만 사용하며, 조회 실패를 빈 목록으로 처리하지 않는다.
- #96 / PR #97에 공유 좌표·스토리·현장 AR·기존 웹 API 구현이 있으나 아직 develop에 병합되지 않았다. 통합 경계와 기존 좌표 변환·소유권 검증을 먼저 확인한다.

## Figma 화면과 데이터 책임

기준: 파일 `nEDJaJBFrdzBCa1WcgADHH`, `2339:2109` 프로토타입 ver.2. 기준 iPhone 프레임은 402×874이며 실제 앱 루트는 가변 크기를 유지한다.

| 플로우 | 원본 노드 | 연동할 책임 |
| --- | --- | --- |
| 지도·검색·선택 | 2379:4070 / 2544:9010 / 2379:4041 | 캠퍼스·구역·공개 오이·공통 ID·위도경도·검색 |
| 요약·스토리 | 2369:3761 / 2450:4928 | 작성자 공개 프로필·테마·감정·본문·순서 있는 사진·공개 상태 |
| AR 수집 | 2861:6643 / 2835:2653 / 2869:7165 / 2855:5505 | 시작·진행 상태, 대상 공개 상태 재확인, 위치·재시도 검증 |
| 수집 결과 | 2869:7162 / 2850:5413 / 2869:7163 | 결과·중복 방지·도감 저장·취소·실패·재도전 |
| MY·농장 | 2744:1732 / 2744:1731 / 2876:7298 | 계정 프로필·등록 오이와 수집 오이 구분·농장 빈 상태 |
| 도감 | 2510:5695 / 2558:9881 / 2558:10110 / 2558:10332 | 계정별 카드·학교별 분류·즐겨찾기·정렬·원본 스토리 연결 |
| 이야기 목록 | 2935:1170 | 본인 초안·접수·공개 상태와 작성 가능 권한; 코인 비활성화 |
| 동의 | 2935:1210 | 문서 버전·동의 시각·필수/선택 동의 구분 |
| 이야기 작성 | 2945:2931 | 테마·감정·제목·본문·사진·위치, 초안 저장·수정 권한 |
| 오이 꾸미기 | 2945:2969 | 이름·포즈·상의·하의·모자, 소유권과 호환되는 외형 |
| 카드 꾸미기 | 2945:3003 | 배경·패턴·크기·테두리와 카드의 원본 오이 관계 |
| 기부 인증 | 2911:752 | 비공개 증빙 업로드·검토 상태·운영자 승인 |

전체 메타데이터와 이야기 작성·목록·인증·수집 실패 화면의 design context 및 스크린샷을 확인했다. 인증 화면은 기본 시스템 바 외에 내용이 없고 일부 접수·꾸미기 화면은 초안이다. 빈 프레임을 완성된 운영 정책으로 취급하지 않는다. 상세 UI 구현 전 해당 화면의 최신 원본을 재확인한다.

## 데이터 및 보안 경계

다음 경계는 적용된 마이그레이션과 iOS 구현의 계약이다.

- Auth 사용자, 비공개 계정 정보, 공개 프로필을 분리한다. 사용자 수정 가능한 메타데이터로 운영자 권한을 판단하지 않는다.
- 증빙과 검토·승인 기록은 비공개로 보관하고 제출자·운영자만 접근한다. 원본 파일의 공개 URL을 발급하거나 로그·스토리·카드에 포함하지 않는다.
- 운영자 검토, 작성 권한, 스토리 공개, 위치 배치, 수집과 즐겨찾기를 서로 다른 상태로 모델링한다.
- 등록 오이의 작성자와 수집 카드의 소유자를 구분한다. 수집자가 원본 이야기·공개 외형을 수정할 수 없어야 한다.
- 저장소의 원본 오이·카드 자산과 꾸미기 선택·호환 규격을 연결한다. 임의 포인트·보상·게임 성공 확률을 만들지 않는다.
- 공개 조회는 공개된 스토리·오이·허용된 프로필과 미디어만 반환한다. 미공개 초안과 Storage 경로 추측으로 자료를 열람할 수 없어야 한다.
- 좋아요·수집·승인 등 중복 요청과 동시 요청에는 DB 제약조건·트랜잭션·멱등성 검증을 적용한다.
- iOS 세션은 Keychain에, PKCE 검증값은 인증 세션 메모리에 보관한다. refresh·로그아웃·계정 전환 때 이전 계정 캐시와 늦게 도착한 응답을 차단한다.

## 적용한 DB와 API

| 마이그레이션 | 책임 |
| --- | --- |
| `20261028081020_oi_flow_foundation.sql` | 학교·구역·실제 프리셋, 공개 프로필, 증빙·작성 권한·이야기·미디어·수집·즐겨찾기, RLS, 비공개 Storage |
| `20261028081058_oi_flow_api.sql` | 소유권·운영자·승인 수량·리비전 검증, 위치 제한, 원자적 상태 전이와 감사 기록 |
| `20261028083035_oi_collection_metrics.sql` | 공개 이야기별 실제 수집 수 집계, 수집자 신원 비노출 |
| `20261028091254_oi_evidence_resubmission.sql` | 보완·거절 신청의 상태 비교 재제출, 이전 파일·검토 이력 보존, 중복 업로드 복구 |

읽기는 `/rest/v1/oi_*`의 RLS를 적용한다. 쓰기는 인증이 필요한 `POST /rest/v1/rpc/oi_mutate`에 `p_action`, `p_payload`를 보낸다. `start_evidence`, `submit_evidence`, `reopen_evidence`, `review_evidence`, `save_story`, `attach_media`, `submit_story`, `reopen_story`, `delete_story`, `review_story`, `collect`, `remove_collection`, `favorite`를 지원한다. 클라이언트의 직접 테이블 쓰기는 프로필의 허용된 열 외에 차단한다.

증빙 승인 수량은 운영자가 매번 명시한다. 기부 금액에 따른 자동 환산은 없다. 삭제한 이야기의 승인 수량은 자동 복원하지 않는다. 위치는 현행 develop의 실제 캠퍼스·건물 경계를 사용하며 캠퍼스 밖과 건물 내부를 거절한다. PR #97의 별도 좌표계를 병합한 것으로 간주하지 않는다.

Storage `oi-evidence`와 `oi-story-media`는 모두 비공개이며 10MB 제한을 적용한다. 증빙은 JPEG·PNG·PDF, 이야기 사진은 JPEG·PNG를 허용한다. 업로드는 덮어쓰기 없이 계정/대상/파일 UUID 경로를 사용하고 재시도에는 바이트 일치를 확인한다. 미디어 조회는 권한 확인 후 5분 서명 URL을 발급한다. 보관 기간 미정이므로 자동 삭제 작업은 추가하지 않았다.

## iOS 사용과 복구

개인 빌드 설정 또는 실행 환경에 `OI_SUPABASE_PUBLISHABLE_KEY`를 주입한다. 클라이언트 공개 키만 허용하며 service-role/secret 키는 앱에서 거절한다. 실제 값은 저장소에 넣지 않는다. Google Auth와 등록돼 있던 `kr.ac.postech.benchmark://auth/callback`을 사용한다.

지도 좌측 농부 → MY → 설정/계정에서 로그인·닉네임·증빙 상태·내 이야기·운영자 검토로 진입한다. 운영자 승인 후 작성 화면에서 실제 프리셋과 사진·야외 위치를 선택하고 서버 초안을 저장한다. 현재 입력의 미리보기를 확인한 후 저장된 최신 리비전으로 공개 검토를 요청한다. 공개 승인은 별도 운영자 동작이다. 공개 이야기만 지도·요약·본문과 도감에 연결한다.

기기 초안과 사진 복사본은 계정별 Application Support에 원자적으로 저장하고 백업에서 제외하며 iOS 파일 보호를 적용한다. 화면을 닫거나 앱을 다시 열어도 복원하고, 명시적으로 버릴 때만 해당 기기 보관본을 삭제한다. 증빙은 동일 신청·파일 ID와 마지막 실패 정보를 보관해 재개한다. 저장 응답을 받은 뒤 목록 조회만 실패하면 저장 완료 안내와 재조회 버튼을 유지한다.

## 검증과 한계

- 원격 PostgreSQL 17에서 `supabase/tests/oi-flow.sql`을 실행했다. 익명·본인·타인·운영자 권한, 비공개 Storage 정책, 승인·수량·리비전 충돌·공개·수집 멱등성·즐겨찾기·승인 취소·보완 이력이 통과했다. 가상 사용자와 Storage 메타데이터는 한 트랜잭션에서 검사한 뒤 전부 rollback했다.
- `supabase/tests/http-smoke.py`는 실제 HTTPS API에서 공개 조회·Google 활성화·집계 조회와 비공개 테이블/익명 쓰기 차단을 확인했다. 이는 사용자 로그인·실제 파일 업로드를 수행한 증거와 구분한다.
- `sh apps/ios/Tests/run-oi-service-checks.sh`: API 구성·페이지 중복 제거·오류 매핑·기기 초안/사진 재실행 복구 검증.
- `OiFlowChecks`의 native 테스트: 저장 후 조회 실패, 사진 연속 첨부, 인증 만료, 오류/빈 상태, 계정 전환 및 지연 응답, 증빙 응답 유실 복구, 최신 수정본 제출을 격리된 URLProtocol과 메모리 세션으로 검증한다. 실제 운영 Keychain은 사용하지 않는다.
- 로컬 검증용 PostgreSQL 18의 결과를 실제 서버 17 검증과 구분한다. 기존 앱의 실제 Google 인증·기기 업로드·물리적 AR 및 현장 수집 정확도는 별도 사용자 검증이 필요하다.
- Xcode 27 / 기존 Swift 5 모드·배포 대상 유지: `OiFlowChecks` 9개 테스트 통과, 375/402/440pt의 계정·작성 화면 렌더링 확인. 실제 iPhone 16 Pro용 Debug 빌드와 `devicectl device install app`도 성공했다. 개인 서명과 공개 키는 임시 프로젝트에만 주입했으며 저장소 설정에 커밋하지 않았다. 설치 후 Google 인증과 실제 파일 제출은 사용자 확인 대상으로 남긴다.
- 기존 `run-architecture-checks.sh`, `run-nfc-checks.sh`, `run-app-clip-checks.sh`, `run-campus-checks.sh`, `run-my-checks.sh` 통과. 기존 `StoryRepository`의 non-final Sendable 경고는 Swift 5 기준 경고로 남으며 이번 작업에서 언어 모드를 변경하지 않았다.

검증 명령은 저장소 루트에서 실행한다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-oi-service-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks \
  -destination 'platform=iOS Simulator,id=<전용 시뮬레이터 UUID>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
python3 supabase/tests/http-smoke.py
```

HTTP 검사에는 개인 환경의 `OI_SUPABASE_PUBLISHABLE_KEY`가 필요하다. SQL 검사는 해당 프로젝트 SQL 실행 도구에서 `supabase/tests/oi-flow.sql` 전체를 단일 트랜잭션으로 실행한다. `bootstrap-local.sql`은 격리된 로컬 검증 전용이며 운영 프로젝트에 적용하지 않는다.

아래 이미지는 실제 Google 계정이 아닌 격리된 가상 세션으로 native 화면을 렌더링한 결과다. 로그인·파일 업로드 완료 증거로 사용하지 않는다.

| 너비 | 계정 | 작성 |
| --- | --- | --- |
| 375pt | [계정](images/supabase-flow/oi-account-375.png) | [작성](images/supabase-flow/oi-editor-375.png) |
| 402pt | [계정](images/supabase-flow/oi-account-402.png) | [작성](images/supabase-flow/oi-editor-402.png) |
| 440pt | [계정](images/supabase-flow/oi-account-440.png) | [작성](images/supabase-flow/oi-editor-440.png) |

## Advisor와 운영 주의

Security Advisor의 비공개 스키마 3개 테이블 `RLS Enabled No Policy`는 클라이언트 접근을 전부 거절하는 의도된 설정이다. GraphQL의 테이블 이름 노출 경고는 REST를 위해 부여한 SELECT 권한에 대한 스키마 발견 가능성 경고이며 실제 행은 동일 RLS로 제한한다. [익명 스키마 노출](https://supabase.com/docs/guides/database/database-linter?lint=0026_pg_graphql_anon_table_exposed), [로그인 사용자 스키마 노출](https://supabase.com/docs/guides/database/database-linter?lint=0027_pg_graphql_authenticated_table_exposed)을 별도로 검토할 수 있다. 기존 Auth의 [유출 비밀번호 보호](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)는 꺼져 있으며 이 작업에서 요금제나 인증 정책을 바꾸지 않았다.

Performance Advisor에는 프리셋 자산 FK 인덱스 2개 누락, 아직 사용 이력이 없는 인덱스, 공개/운영자 조회 정책 중첩이 남는다. 지금 데이터 크기에서는 불필요한 인덱스/정책 변경을 추가하지 않았으며 실제 사용량을 보고 개선한다. 이것을 보안 차단 실패나 검사 통과로 바꿔 보고하지 않는다.

이번 마이그레이션은 기존 표·Auth 계정을 제거하지 않는 추가 변경이다. 문제 발생 시 새 클라이언트 사용을 중단하고 운영자가 공개/작성 승인을 회수해 노출을 차단한다. 마이그레이션 기록을 삭제하거나 표·Storage를 일괄 drop하는 자동 롤백은 제공하지 않는다. 이미 접수한 파일과 이야기 보존 범위를 확인한 뒤 별도 복구 마이그레이션으로 처리한다.

Needs confirmation:
- 수집 성공 조건·거리/방문 인증·삭제 후 승인 수량 복원·재수집 정책, 꾸미기 자산의 호환 규격. 현재 수집 저장은 공개 이야기의 계정별 등록이며 AR 게임 성공이나 실제 방문 증명을 대신하지 않는다.
- 증빙 수집 항목·인정 기준·보관 기간, 최종 약관/동의문과 버전 관리. 현재 증빙 UI는 가상 자료를 사용하는 내부 검증용이다.

위 미정 정책을 데이터베이스의 임의 상수나 자동 승인으로 대신하지 않는다.

## MY 실데이터 전환 — 2026-10-30 / #107·#100 후속

사용자 요청으로 MY의 예시 생성·가상 학교·로컬 즐겨찾기 성공 경로를 제거했다. `MYLibraryStore`는 서버 목록의 화면 투영만 맡고, 수집·핀 저장은 기존 `oi_mutate`의 응답 이후에만 반영한다. 계정 전환 시 목록과 정렬·핀 필터를 초기화한다. 지도도 예시 스토리·가상 수집 기록·고정 기부 통계를 생성하지 않는다. 레거시 미연동 기부·명패 메뉴는 현재 MY 진입에서 제거했다.

학교·구역·자산 목록은 `oi_schools`, `oi_regions`, `oi_assets`에서 조회한다. 학교 선택은 본인의 `oi_profiles.school_id`에 저장하며 닉네임과 함께 재시작 후 복원한다. 기존 FK·RLS와 프로필 허용 열을 재사용하므로 신규 스키마 변경은 필요하지 않았다. 기존 프로젝트·Auth 사용자·증빙·이야기는 삭제하지 않는다.

정적 카드 안의 다른 사람 이야기·기부 횟수는 더 이상 표시하지 않는다. 실제 오이 외형·이름·본문·작성자·날짜와 저장된 카드 배경 선택을 SwiftUI에서 합성한다. 농장은 실제 본인 이야기 목록·공개 상태를 표시한다. 빈 목록을 채우기 위한 스토리를 운영 DB에 추가하지 않는다.

`RealStoryRepository`의 빈 반환 구현도 실제 공개 Supabase 조회로 교체했다. App Clip과 앱이 같은 공개 이야기 ID·본문을 조회하며 소유자·운영자 토큰을 사용하지 않는다. 숨김·삭제 이야기는 표시하지 않고, 이미지가 없는 카드에 가짜 URL을 만들지 않는다. App Clip의 기기 보관과 계정 도감 저장은 구분하며, 전체 앱에서 로그인 후 ‘내 계정 도감에 저장’을 실행해 서버 응답을 확인한 뒤 기기 대기 항목을 제거한다.

### 로컬 실행 설정

키 값은 Git에 넣지 않는다. 아래 스크립트는 기존 프로젝트의 공개 키만 두 앱의 Git 제외 `Service.local.plist`에 저장한다. 새 Supabase 프로젝트나 키를 생성하지 않으며 비밀 키를 요구하지 않는다. 기존 로컬 파일이 다른 값이면 덮어쓰지 않는다.

```sh
python3 scripts/configure-ios-service.py --from-cli --http-check
```

CI는 `OI_SUPABASE_PUBLISHABLE_KEY` 환경변수와 `python3 scripts/configure-ios-service.py`를 사용한다. 두 plist는 각 앱의 파일 시스템 동기화 그룹으로 리소스에 포함된다. 공개 키라도 실제 값은 로그·커밋·PR에 남기지 않는다. 외부 호스트로의 리다이렉트는 기존 APIClient가 차단한다.

### 실제 서버와 자동 검사

- 실제 프로젝트: `52gibu`, `kfzfzarslqdqmrazohej`, ACTIVE_HEALTHY. 기존 5개 마이그레이션을 확인했다. 공개 이야기·수집은 조회 당시 각각 0건이었으며 가짜 기록을 채우지 않았다.
- `supabase/tests/oi-flow.sql`에 학교 저장·잘못된 학교 FK 거절을 추가해 실제 PostgreSQL 17에서 실행했다. 프로필·승인 전 작성 차단·소유권·비공개 Storage·공개·수집·핀·리비전·증빙 재제출 검사는 통과했고 전체 가상 자료는 rollback했다.
- 위 설정 명령의 `--http-check`가 실제 HTTPS 익명 공개 조회·비공개 테이블 접근 차단·익명 쓰기 차단·집계·Google provider 활성화 검사에 통과했다.
- `sh apps/ios/Tests/run-my-checks.sh`, `run-campus-checks.sh`, `run-architecture-checks.sh`, `run-app-clip-checks.sh`, `run-oi-service-checks.sh`를 Xcode 27 도구 체인으로 실행했다. 예시 생성 검사는 서버 응답 전 성공 금지·계정 격리·실제 목록 투영 검사로 대체했다. 테스트 안의 격리 fixture는 운영 앱에 포함하지 않는다.
- `OiFlowChecks` native 11개 검사에서 학교 저장·재시작 복원·잘못된 학교 차단, 실제 공개 Repository의 본문·ID·숨김 거절, 기존 업로드 재시도·인증 만료·계정 전환 검사가 통과했다. 이 검사는 격리된 URLProtocol을 사용하며 실제 Google 로그인 성공 증거와 구분한다.
- Security Advisor의 기존 GraphQL 스키마 발견 경고, private 스키마의 의도된 RLS 전면 차단, 유출 비밀번호 보호 비활성은 별도 운영 항목이다. 이 변경으로 Auth 정책·요금제를 수정하지 않았다.

Needs confirmation:
- 실제 Google 계정 로그인·사용자 파일 업로드·실기기 권한과 AR 정확도는 사용자 인증이 필요한 검증이다. 자동 성공으로 표시하지 않는다.
- 실제 증빙 접수의 인정 기준·담당자·보관 기간·최종 동의문은 여전히 운영 결정이다. 최소 금액·피클코인·성장·옷 슬롯 정책을 새로 확정하지 않았다.

### 실행 명령과 최종 실제 화면

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug -destination 'platform=iOS Simulator,id=6CC1A80E-70DB-474F-A605-0229DCB82D04' -parallel-testing-enabled NO -derivedDataPath /private/tmp/benchmark-live-build -resultBundlePath /private/tmp/benchmark-live-native-final.xcresult CODE_SIGNING_ALLOWED=NO test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project /private/tmp/benchmark-mylive-qa/OiDonation.xcodeproj -scheme MYQA -configuration Debug -destination 'platform=iOS Simulator,id=53588BEC-519B-49BE-9EDF-1DD86CC88992' -parallel-testing-enabled NO -derivedDataPath /private/tmp/benchmark-mylive-ui-build -resultBundlePath /private/tmp/benchmark-mylive-ui-signed.xcresult CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiDonation -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/benchmark-live-build CODE_SIGNING_ALLOWED=NO build
```

실제 52gibu API를 사용하는 UI 검사에서 수집 0개·빈 학교 목록·로그인 전 농장·Google 로그인 진입을 확인했다. 최초 무서명 Simulator에서는 Keychain 접근 오류가 일반 연결 오류로 표시되는 것을 캡처로 발견했다. 계정 저장소 오류를 별도 오류 코드로 구분하고, 정상 로컬 서명 빌드로 같은 실제 서비스 UI 검사를 다시 실행해 오류 없는 로그인 진입이 통과했다. 실제 Google 계정 인증을 완료한 검사가 아니다. 원본 앱·Clip 타깃의 팀·Bundle ID·권한은 변경하지 않았다.

최대 동시 실행 리소스는 3그룹(검사 실행기·전용 기기·검사 앱)이었다. 전용 Simulator 두 대는 검사 후 삭제했고 실행기·앱 종료와 빈 booted 목록을 확인했다. 완료 시점에 별도로 요청한 `simctl screenshot` 명령 하나가 종료된 기기를 기다려 남은 것을 확인하여 정확한 PID에 TERM을 보내 종료했다. 최종 캡처는 성공한 XCTest 첨부에서 추출했다. Computer Use 세션·커서·가시/숨김 창·브라우저·승인 터미널은 만들지 않았고 남긴 실행 리소스는 없다.

![실제 서버의 빈 계정 도감](../apps/ios/docs/verification/mylive/collection.png)
![정상 로컬 서명에서 실제 로그인 진입](../apps/ios/docs/verification/mylive/account.png)
