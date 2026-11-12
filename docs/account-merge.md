# Google·Apple 앱 계정 통합

이 기능은 Supabase Auth 사용자·identity를 삭제하거나 다른 사용자에게 옮기지 않는다. 두 로그인 계정을 검증한 뒤 앱의 데이터 소유권을 사용자가 고른 대표 계정으로 합친다. Google·Apple 로그인은 각각 기존 Auth 사용자 ID를 유지하며 서버가 대표 앱 계정 ID를 해석한다.

## 동의와 데이터 보존

- 대표 계정의 닉네임·학교를 유지한다. 이야기·증빙과 기존 작성 승인 이력의 ID·상태는 바꾸지 않는다. #234 이후 과거 작성 승인 이력은 앱 이용 권한을 결정하지 않는다.
- 수집·즐겨찾기는 합집합으로 만들고 중복의 가장 이른 등록일을 유지한다.
- 증빙·사진 객체는 이동하지 않는다. `storage_owner_id`에 원래 경로 소유자를 보존해 기존 경로를 계속 검증한다.
- 어느 계정 그룹에든 운영자 계정이 있으면 통합하지 않는다.
- 두 계정에서 10분 이내 새 OAuth 로그인이 필요하다. JWT의 `iat`만 새로워지는 토큰 갱신은 재인증으로 인정하지 않는다.
- 통합 직후 기존 다른 세션의 비공개 접근은 차단한다. 검증한 두 세션과 통합 이후 새로 생성된 세션만 허용하며 세션 존재·사용자 일치도 DB에서 확인한다.
- 실제 통합 후 계정 분리는 자동 지원하지 않는다. 확인 화면에서 대표 계정·통합 개수와 이 제한을 안내하고 명시적 동의를 받는다.

## 클라이언트 계약

기존 `oi_capabilities`는 `operator`, `coins_enabled`를 유지하며 `account_merge_enabled`, `account_id`, `account_member_ids`, `account_providers`를 추가한다. 구버전 서버에 추가 필드가 없으면 기존 Auth 사용자 ID를 그대로 사용하고 통합 UI를 비활성화한다. `oi_account_context()`는 `{id, auth_user_id, email:null, member_ids, account_providers}`를 반환한다. provider 라벨은 인증된 계정 그룹의 `auth.identities`를 서버에서 조회한 Google·Apple 값만 반환하며, 이메일·identity 원문이나 메타데이터를 노출하지 않는다.

토큰의 실제 사용자 ID와 앱의 대표 ID를 구분한다. 세션 저장·갱신에는 실제 Auth ID를, 앱 데이터 필터·프로필에는 대표 ID를 사용한다. 로컬 초안은 `account_member_ids`로 확인된 계정에 대해서만 복구하며, 같은 초안 ID가 충돌하면 기존 파일을 덮어쓰지 않는다. 사진·증빙 경로는 각 행의 `storage_owner_id`를 사용하고 구버전 서버에서는 해당 행의 `user_id`를 사용한다.

`account-merge` Edge Function에 POST한다. Authorization은 대표로 선택한 계정의 최근 access token이다. 본문은 다음 필드를 사용한다.

- 공통: `action`(`preview`/`confirm`), `source_access_token`, `operation_id`(시도마다 새 UUID, 같은 요청 재시도에는 유지).
- `preview` 응답: `challenge_id`, `target_account_id`, `source_account_id`, `source_is_new`, `expires_at`, `counts`(통합 후 합집합 기준 이야기·수집·즐겨찾기·증빙·승인 개수).
- `confirm`: `challenge_id`, `consent:true` 추가. 성공 응답은 `{account_id, already_merged}`다.

미리보기 challenge는 양쪽 Auth 사용자·세션·대표 계정과 연결되고 5분 동안만 유효하다. 확인은 한 번만 소비하며, 응답을 잃은 같은 작업의 재시도는 저장된 영수증을 반환한다. 두 계정·작업 ID·challenge를 바꿔 재사용하면 실패한다. 단말의 대표 ID·이메일·사용자 메타데이터는 소유권 증명으로 받지 않는다.

`source_is_new`는 최근 OAuth 증명의 10분 범위 안에 생성됐고 이번 증명 세션 이외의 현재 세션이 없으며, 독립된 기본 프로필·학교 미선택·앱 기록이 없는 최근 미사용 계정에서만 참이다. PKCE 콜백과 앱의 code exchange 사이에는 수십 초가 걸릴 수 있으므로 1초 이내 교환을 요구하지 않는다. 이 값은 최초 가입을 암호학적으로 증명하지 않는 화면 분류 힌트다. 오래된 사용자·복수 세션·사용 기록·프로필 변경 등이 있으면 기존 계정 통합 검토로 전환한다. 두 흐름은 같은 추가 provider 인증 증명을 유지하며 모두 미리보기·명시적 확인을 거친다. 미리보기 후 개수나 새 계정 분류가 바뀌면 `merge_account_changed`로 중단하고 같은 두 증명으로 미리보기를 갱신할 수 있다. 이때 provider 인증을 다시 시작할 필요는 없다.

## 서버 적용 경계

아직 실제 DB/Auth/Storage 변경이나 함수 배포를 수행하지 않았다. 적용 전 운영 담당자가 마이그레이션과 두 provider의 실제 로그인 증명을 검증해야 한다.

1. `20261103062732_oi_account_merge.sql`을 검토한다. DB 소유권·RLS·Storage 검사와 계정 통합은 하나의 트랜잭션 경계를 사용한다. 기존 사용자 등록 함수는 덮어쓰지 않고 프로필 INSERT에 별도 앱 계정 등록 트리거를 추가한다.
2. 현재 소유 RPC의 알려진 기본/배포 버전만 제한적으로 변환한다. 배포 버전의 `save_campus_story`, `height_meters`, `heading_degrees` 지원을 유지한다. 알 수 없는 RPC 정의 드리프트는 전체 마이그레이션을 중단하며 원본을 덮어쓰지 않는다.
3. 새 마이그레이션이 먼저 준비된 뒤 `account-merge` 함수를 배포한다. 함수는 런타임의 `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`를 사용한다. service-role 키는 앱·Git에 넣지 않는다. SQL `oi_merge_accounts`는 service_role만 실행할 수 있다.
4. 새로 서명된 두 provider 세션으로 실제 검증 후 UI를 공개한다. 운영자 통합은 허용하지 않는다. Apple provider 설정·실기기 로그인·실제 통합은 별도 검증 대상이다.

이미 실제 통합을 수행한 DB에서 매핑·소유자 열을 단순 삭제하는 롤백은 안전하지 않다. UI/함수를 먼저 비활성화하고 기존 대표 매핑을 유지한 채 개별 복구 계획을 검토해야 한다.

## 검증

```sh
npm --prefix supabase test
python3 supabase/tests/run-account-merge-db-checks.py
```

두 번째 명령은 설치된 PostgreSQL 도구만 사용해 임시 Unix 소켓 전용 DB 하나를 시작하고 종료한다. 공유 서버나 실제 Supabase에는 연결하지 않는다. 기존 SQL 회귀·합집합·상태/프로필/경로 보존·동의·운영자 제외·중간 실패 롤백·세션 차단·동시 반대 방향 통합·배포 RPC 호환성과 드리프트 차단을 확인한다. 실패 시 DB를 종료하고 로그 경로를 표시한다.
