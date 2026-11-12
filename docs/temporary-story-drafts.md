# 임시 작성 모드 — 2026-11-04 / #148

> 아래는 #148 당시 기록이다. 2026-11-08 #234가 적용되면 `unapproved_drafts_enabled`는 전체 작성 일시 중지 스위치로 사용한다. OFF여도 기부 증빙으로 작성 권한을 얻을 수 없다. 최신 동작과 배포 순서는 [Supabase 연동 문서](supabase-flow.md)를 따른다.

기존 Supabase 전체 플로우 #100의 후속 작업이다.

사용자 확정: 최초 작성 승인 없이 이야기·사진·위치·오이/카드 설정을 저장하고 검토 요청을 시험한다. 모드 종료 후에도 글과 사진을 보존한다. 로그인, 본인 데이터 접근, 운영자 공개 승인은 유지한다. 임시 작성은 실제 기부 확인이 아니다.

## 상태별 동작

| 조건 | 새 작성·서버 저장·사진 업로드·검토 요청 | 기존 자료 |
| --- | --- | --- |
| 임시 모드 ON, 승인 연결 없음 | 가능. `grant_id=null`, 저장은 draft, 검토 요청은 pending | 작성자만 초안/사진 조회 |
| 모드 OFF, 승인 연결 없음 | 차단. 앱에서 승인 상태 새로고침 가능 | 같은 ID·본문·사진·상태 보존, 작성자 조회 가능 |
| 유효한 승인 연결 | 기존 승인 수량·revision 조건 적용 | 기존 흐름 유지 |
| 취소된 승인 연결 | 임시 모드 ON이어도 저장 불가 | 승인 연결을 임의 제거해 우회 불가 |
| 비로그인/다른 작성자의 초안 | 쓰기 불가 | 비공개 초안/사진 접근 불가 |

모드를 끌 때 이미 공개된 이야기를 자동 비공개로 바꾸지 않는다. 미승인 pending 이야기는 모드 OFF 중 새 공개 승인도 차단한다. 작성자의 숨김/수정 시작·삭제와 운영자의 숨김은 기존 소유권/상태 조건으로 처리한다. 수정 시작은 내용을 지우지 않고 draft로 되돌린다.

## DB/API

- `20261104120000_oi_temporary_story_drafts.sql`: `oi_stories.grant_id`의 NOT NULL만 제거하고 FK는 유지한다.
- 설정은 `benchmark_private.oi_story_creation_settings`의 singleton 행에 보관한다. 기본값 false, 일반 사용자 직접 조회/수정 불가.
- `oi_capabilities()`의 `unapproved_drafts_enabled`로 앱이 현재 모드를 확인한다. 필드가 없는 구형 서버에서는 false로 처리한다.
- `oi_mutate('save_story', ...)`: grant_id가 JSON null/생략이면 ON에서만 허용한다. 전달한 승인 ID는 항상 소유권·취소 여부를 검사한다. 임시 초안에 유효 승인을 연결할 때도 승인 수량을 검사한다. 이미 승인에 연결된 이야기는 다른 승인으로 변경하거나 null로 제거할 수 없다.
- 모든 이야기 mutation은 설정 행 공유 잠금으로 모드 변경과 순서를 맞춘다. 같은 이야기 ID 쓰기는 advisory lock으로 직렬화하고 기존 revision 검사도 유지한다.
- Storage `oi-story-media`의 기존 경로/소유권 정책에 승인 조건을 추가한다. OFF 시 INSERT만 차단하고 SELECT 정책·사진 바이트·첨부 연결은 변경하지 않는다. 업로드 후 종료되면 파일을 지우지 않으며 승인 후 재시도할 수 있다.
- 기존 기준 RPC와 배포된 `save_campus_story`/높이/방향 확장 RPC 두 소스 해시만 허용한다. 다른 정의이면 마이그레이션 전체가 롤백되므로 원격 SQL을 확인해 패치를 재검토한다.

## iOS

`OiLiveStory.grantId`는 optional, `OiStoryDraft.valid`는 내용만 검사하고 권한은 `OiWritingAccess`/`OiRemoteStore`가 구분한다. 임시 모드의 새 초안은 가짜 승인을 선택하지 않는다. 승인 없이 작성 가능하다는 안내와 공개 검토가 필요하다는 안내를 분리한다.

모드 OFF 뒤 새 서버 저장/제출은 막히며 기존 계정별 기기 초안 자동 저장을 중단하거나 삭제하지 않는다. 목록에서 같은 초안을 열고 ‘작성 권한 새로고침’ 후 실제 승인에 연결할 수 있다. 서버가 모드를 변경한 직후 앱에 이전 상태가 남아 있어도 DB/API에서 거절한다. 서버 설정 변경 후 목록 새로고침 또는 앱 재진입으로 최신 정책을 확인한다.

2026-11-08 #218. 이야기 목록과 기부 자료 화면은 조회한 `unapproved_drafts_enabled` 값에 따라 작성 조건을 표시한다. 목록은 로그인 전에는 로그인 안내를, 조회 실패 시에는 일반 작성 안내를 표시한다. 기부 안내와 조회에 실패한 기부 자료 화면에서는 모드별 조건을 함께 설명한다. 공개 승인과 공식 납입 확인은 각각의 절차로 안내한다. 실제 이야기 목록의 씨앗 및 고정 저장 개수 문구는 작성·공개 절차 안내로 교체한다.

커스텀 색·의상/사진 레이어는 기존 계정별 기기 초안에 저장된다. 이 변경은 공유 커스텀 외형 API를 추가하지 않으며 공개 지도/AR에는 기존 서버 프리셋이 사용된다.

## 배포 및 모드 전환

1. 대상 프로젝트가 `52gibu` (`kfzfzarslqdqmrazohej`)인지 확인하고, 선행 account merge/card request 마이그레이션 적용 상태를 확인한다.
2. 새 iOS 빌드를 테스트 계정/기기에 배포한다. 기존 빌드는 null grant를 디코딩하지 못할 수 있으므로 테스트에 쓰지 않는다.
3. 새 SQL 마이그레이션을 적용한다. 적용 직후는 OFF다. 소스 drift 오류가 나면 우회해서 함수를 덮어쓰지 않는다.
4. 운영자 세션의 RPC `oi_set_unapproved_drafts(p_enabled:true)`로 켜고 false로 끈다. 일반 계정에서는 42501 오류가 나야 한다.
5. Supabase SQL Editor의 DB 관리자 세션에서는 아래 쿼리로 전환할 수 있다. 클라이언트에 DB/service-role 키를 배포하지 않는다.

```sql
-- 켜기 (끄려면 true를 false로 바꾼다)
update benchmark_private.oi_story_creation_settings
set unapproved_drafts_enabled = true, updated_at = now()
where singleton
returning unapproved_drafts_enabled;
```

설정 OFF가 복구 절차다. 이전 NOT NULL 제약을 다시 추가하거나 미승인 행·사진을 삭제하지 않는다.

## 검증

- `python3 supabase/tests/run-account-merge-db-checks.py`: 격리 PostgreSQL에서 기본/배포 변형 양쪽 마이그레이션, 모드 전환, 비인가 접근, Storage, 승인 연결·수량·취소, 기존 계정 통합/카드 요청 검사.
- `sh apps/ios/Tests/run-oi-service-checks.sh`: nullable 승인 payload, 구형 서버의 기본 OFF, 승인 취소와 임시 모드 권한, 기존 초안/사진 보관 검사.
- `OiFlowChecks`의 `OiRemoteStoreTests.testTemporaryWritingFlagPreservesStoryAndPhotoWhenDisabled`: 서버 capability 반영, 승인 없는 저장/사진, OFF 뒤 자료 보존, 승인 연결 재개, 로그아웃 권한 초기화.
- 원격 적용·일반 계정 실제 저장·실기기 전체 화면 확인 여부는 배포 시 별도로 기록한다. 로컬 검사 성공만으로 원격 활성화로 간주하지 않는다.

### 이번 작업의 확인 결과

2026-11-04 로컬 기본/배포 변형 DB 회귀 검사 및 알 수 없는 RPC 변경 시 롤백 검사 통과. Swift 서비스/초안 검사 통과. iOS 시뮬레이터 `OiFlowChecks` 52개 통과 후 마지막 변경을 포함한 임시 작성 전환 테스트 1개도 재실행해 통과했다.

같은 날 사용자의 현재 앱 활성화 요청에 따라 `52gibu`에 `20261104120000` 마이그레이션을 적용하고 이력을 기록했다. DB 관리자 세션에서 `unapproved_drafts_enabled=true`로 전환했으며, `oi_stories.grant_id`가 nullable인 것을 확인했다. 적용 전 기존 RPC 해시와 account merge/card request 선행 마이그레이션을 확인했다.

원격 DB에서 작성 승인이 없는 일반 계정 문맥과 `authenticated` 역할로 초안 저장 → 비공개 Storage 객체 메타데이터 INSERT → 사진 연결 → 검토 요청을 검증했다. 승인 연결은 null이고 요청 결과는 pending이었다. 가상 데이터는 한 트랜잭션에서 검사한 뒤 rollback했으며 이야기·사진 연결 건수는 전후 동일했다. 실제 사진 바이트 업로드나 사용자 OAuth 로그인까지 검증한 것은 아니다. 모드 OFF 시 보존·재승인 흐름은 위 격리 DB/앱 테스트에서 확인했다.

개인 수동 서명 설정을 저장소 밖에서 사용해 실기기 빌드가 성공했고, `Jun iPhone`에 `com.Spero.OiDonation`을 업데이트 설치·실행했다. 해당 iOS 버전에서는 Device Hub 화면 공유가 지원되지 않아 실제 iPhone의 작성 화면 조작은 직접 검증하지 못했다. 앱에 로그인한 뒤 지도 `+` → `오이 만들기`에서 임시 작성 안내를 확인하고 진행한다. 공개 지도 반영은 여전히 운영자 공개 승인 후 가능하다.
