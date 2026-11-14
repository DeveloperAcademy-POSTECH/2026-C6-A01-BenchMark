# NFC 스크래치 엽서 · #291

2026-11-13 사용자 확정. 교내 NFC 태그를 대면 App Clip이 서버의 공개 이야기를 스크래치 엽서로 보여 주고, 수집 기록을 남겨 전체 앱 설치를 안내한다. 제품 결정과 미정 항목은 [project.md](../project.md#2026-11-13-nfc-스크래치-엽서--291)를 따른다.

## 흐름

1. 태그 URL: `https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip&postcard=<태그 ID>`. 태그 ID는 영어 소문자·숫자·`-`, 1~40자다.
2. App Clip이 `oi_nfc_postcard(<태그 ID>)`로 이야기 ID를 받는다. 활성 태그이면서 이야기가 공개 상태이고 작성자가 제한·탈퇴 중이 아닐 때만 값이 나온다.
3. 공개 이야기(오이 이름·테마·감정·구역·공개일·본문), 승인된 엽서 앞면과 뒷면, 첫 이야기 사진, 오이 캐릭터, 작성자의 공개 기부자 정보(이름·학과·입학연도)를 받는다. 기부자 정보가 없으면 닉네임을 쓴다.
4. 첫 사진을 흐리게 깐 카드를 긁으면 승인된 앞면이 나오고, 뒤집으면 뒷면이 보인다. 사진이 없으면 앞면을 표지로 쓴다. 앞면 카드가 없거나 뒷면 이미지가 없는 이전 이야기는 기본 글꼴로 대신 그린다.
5. **앨범에 저장하기**는 저장 직전에 공개 이야기와 태그 연결을 서버에서 다시 확인한다. 중지·교체·비공개 또는 네트워크 실패면 새 수집을 막고, 확인된 경우에만 App Group의 기존 App Clip 수집 기록(`StoryCollectionStore`)에 이야기 ID를 남긴다. 전체 앱은 도감의 "App Clip에서 수집한 카드"에서 서버의 최신 공개 이야기를 다시 조회해 표시한다.
6. **이어서 기부하기**는 전체 앱 설치 안내(SKOverlay)를 연다.

전체 앱이 설치된 iPhone은 태그를 대면 App Clip 대신 전체 앱이 열린다. 전체 앱의 `postcard=` 처리는 아직 없다(미정).

## 서버 (`20261113090000_oi_nfc_postcard_tags.sql`)

| 이름 | 권한 | 역할 |
| --- | --- | --- |
| `benchmark_private.oi_nfc_tags` | 직접 접근 불가 | 태그 ID·이야기·사용 여부·설치 위치 메모 |
| `oi_nfc_postcard(p_tag)` | 익명·로그인 | 공개 가능한 이야기 ID 또는 null |
| `oi_operator_set_nfc_tag(p_tag, p_story, p_active, p_note)` | 운영자 | 태그 생성·연결·교체·중지, 감사 기록 `nfc_tag:link`/`nfc_tag:unlink` |
| `oi_operator_nfc_tags()` | 운영자 | 모든 태그와 연결된 이야기 제목·상태 |

카드 이미지는 #308의 `card_snapshot_format=2`와 네 파일 검토 계약을 공유한다. 별도 `-back.png` 정책은 만들지 않는다. 이전 형식 1은 앞면만 읽고 뒷면은 기존 본문 표시로 대체한다. 형식 2의 뒷면 조회·다운로드 실패는 재시도로 안내하고 대체 문구로 숨기지 않는다. 이야기가 삭제되면 태그는 남고 연결만 비워진다.

### 운영자 태그 연결

2026-11-13 #310: 본 앱 MY 설정 → 운영자 관리 → **NFC 태그**에서 관리한다.

- 목록: 태그 ID, 연결된 이야기 제목, 설치 위치 메모, 상태(엽서 열림 / 검토 대기 / 비공개 / 삭제 / 연결 없음 / 중지). 열리지 않는 태그를 바로 구분한다. 중지된 태그는 기본으로 숨기고 토글로 볼 수 있다. 붙인 태그의 ID가 다른 이야기에 재사용되지 않도록 삭제 기능은 두지 않고 사용 중지로 대신한다.
- 추가·수정: 태그 ID(새 태그는 `oi-` + 혼동 글자를 뺀 무작위 6자를 자동으로 채우고 수정 가능, 형식 검사·중복 안내, 저장 직전 목록을 다시 받아 같은 ID가 생겼으면 덮어쓰지 않음), 공개·검토 대기 이야기 검색·선택 또는 연결 해제, 사용 켜기/끄기, 메모 200자. 저장 전에 확인 창을 띄운다.
- 태그 URL 표시·복사. 태그 기록과 잠금은 시중 NFC 기록 앱으로 한다.
- `oi_operator_nfc_tags`·`oi_operator_set_nfc_tag`를 호출하며 서버가 운영자 권한을 다시 확인하고 감사 기록(`NFC 태그 연결`/`연결 해제·중지`)을 남긴다. 응답의 태그·이야기·사용 여부가 요청과 다르면 저장 성공으로 표시하지 않는다. 서버에 함수가 없으면 마이그레이션 적용 상태를 안내한다.

화면을 쓸 수 없을 때는 운영자 계정으로 로그인한 세션에서 RPC를 호출한다.

```sql
-- 연결하거나 다른 이야기로 바꾸기
select public.oi_operator_set_nfc_tag('pond-01', '<이야기 UUID>', true, '지곡회관 옆 연못 벤치');
-- 태그 중지 (태그를 대도 엽서가 나오지 않음)
select public.oi_operator_set_nfc_tag('pond-01', '<이야기 UUID>', false, '지곡회관 옆 연못 벤치');
-- 목록
select public.oi_operator_nfc_tags();
```

SQL 편집기처럼 서비스 역할로 직접 실행하면 운영자 확인을 통과하지 못한다. 운영자 JWT로 호출해야 한다. 운영자 화면이 생기기 전에 Supabase SQL 편집기만 쓸 수 있다면 표를 직접 수정할 수 있지만, 이 경우 감사 기록이 남지 않으므로 작업자·시각·이유를 따로 기록한다.

```sql
insert into benchmark_private.oi_nfc_tags(tag_id, story_id, active, note)
values ('pond-01', '<이야기 UUID>', true, '지곡회관 옆 연못 벤치')
on conflict (tag_id) do update set story_id = excluded.story_id, active = excluded.active,
  note = excluded.note, updated_at = now();
```

## 앱

- 공개 검토 요청은 #308의 1086×1506 양면 원본과 724×1004 양면 미리보기를 한 버전으로 제출한다. 본문만 고쳐도 뒷면과 버전 ID를 갱신하며, 서버 앞면을 재사용하는 경우에도 새 본문으로 뒷면을 만든다. [저장·승인 계약](duplex-story-cards.md)을 따른다.
- 운영자는 양면 원본과 미리보기를 모두 확인해야 형식 2를 승인할 수 있다. 검토하지 않은 별도 파일은 공개하지 않는다.
- App Clip: `ScratchPostcardScreen`(불러오기·볼 수 없음·재시도) → `ScratchPostcardView`. 이미지는 승인된 Supabase 호스트의 5분 서명 URL에서만 받는다. 앱에 넣어 둔 예시 엽서와 이미지는 제거했다.

## 적용 순서

1. **운영 적용 완료: 2026-11-13 17:01:23 KST(CLI 완료 시각).** 52gibu에 `20261113090000_oi_nfc_postcard_tags.sql` 한 개와 배포 이력만 같은 트랜잭션으로 적용했다. #311의 `20261113070000`은 재적용하지 않았다. 아래 운영 검증 기록을 따른다.
2. 새 앱 빌드(Xcode·TestFlight)로 NFC용 이야기를 작성하고 공개 검토를 요청한다. 운영자가 앞·뒷면을 확인하고 승인한다.
3. 운영자가 태그를 연결한다.
4. Xcode `OiDonationClip` 스킴의 `_XCAppClipURL`을 태그 URL로 바꾸거나 App Store Connect의 App Clip 테스트 링크로 확인한다.
5. 앱 업데이트를 심사·출시한 뒤 실제 iPhone으로 태그를 확인하고 잠금(lock) 후 부착한다.

## 검증 (2026-11-13)

- `supabase/tests/run-account-merge-db-checks.py`: 기존 마이그레이션 전체와 새 파일을 임시 로컬 PostgreSQL 17에 적용했다. 기존 검사와 `oi-nfc-postcard-tags.sql`(권한, 태그 형식, 공개·중지·교체·숨김·삭제, 감사, 뒷면 공개 범위)이 통과했다.
- iOS: App Clip·전체 앱 시뮬레이터 빌드와 `Tests/run-app-clip-checks.sh`가 통과했다. 임시 가짜 저장소로 App Clip 시작 화면과 볼 수 없는 태그 화면을 시뮬레이터에서 확인했다(임시 코드는 제거).
- App Clip 용량: Release 아카이브를 개발 서명·전체 기기 변형으로 내보내 `scripts/check-app-clip-release.py`로 측정했다. 양진체(1.7MB)를 넣으면 iPhone 변형이 16,022,792바이트로 15MB를 넘어 제거했고, 제거 후 통합 수정본 최대 14,341,765바이트(기기별 약 14.11~14.19MB)로 통과했다. `run-app-clip-font-checks.sh`도 통과했다. 정보 칸 이름은 Figma의 리틱체(REATIC) 대신 Paperlogy Bold를 쓴다. 리틱체는 라이선스가 임의 수정·무단 재배포를 금지해 앱 탑재 허락이 필요하고, 파일 하나가 약 2.7MB라 허락을 받아도 App Clip에는 용량 조정이 함께 필요하다.
- 미검증: 실제 계정으로 뒷면 PNG 업로드·운영자 검토 표시, 실제 서버 데이터로 App Clip 표시, 손가락 긁기·뒤집기·대체 뒷면 표시, 실기기 NFC 호출.

## #307·#311 통합 수정 (2026-11-13)

NFC 태그·스크래치 UI는 유지하고 카드 모델·생성·업로드·검토는 #311 구현으로 통일했다. 신규 NFC 조회는 승인된 `front-preview.png`·`back-preview.png`를 읽는다. 잘못 공개되던 별도 `snapshot-back.png` 경로를 제거하고 회귀 검사에 이 파일의 비공개 보장을 추가했다. 저장 직전 공개·태그 재확인과 중복 요청·취소 처리를 적용했다. 통합 수정 당시 미적용이던 `20261113090000`은 아래 운영 적용 기록과 같이 배포했다. 이미 승인·적용된 #308의 `20261113070000`은 변경하지 않았다.

통합 회귀 검증: 로컬 PostgreSQL 전체 마이그레이션·권한 검사와 App Clip 명령행 검사를 통과했다. `OiFlowChecks` 관련 89건 중 86건 통과·명시적 opt-in 3건 건너뜀·실패 0건이다. 형식 2의 뒷면 조회 실패, 태그 중지·교체, 비공개 전환, 네트워크 실패 시 수집 방지와 검토되지 않은 별도 뒷면의 비공개를 확인했다. 본 앱·App Clip Release 아카이브, 전체 변형 내보내기, 15MB 용량 검사와 글꼴 검사도 통과했다.

## 운영 적용·검증 — 2026-11-13 (#291)

- 사용자 명시 승인에 따라 최신 develop `677b3be`의 파일을 사용했다. `2c7cc92`의 통합 수정본과 동일하며, 끝의 `Card files use the reviewed format-2 contract` 주석과 원본 일치를 확인했다.
- 적용 전 읽기 전용 검사(17:00:12 KST): 최근 이력의 최신 버전은 `20261113070000`, NFC `20261113090000`은 없었다. NFC 비공개 표와 세 함수 모두 없었다.
- Supabase CLI의 52gibu 명시 대상 SQL 실행으로 해당 파일과 `schema_migrations` 이력 한 행을 **단일 트랜잭션**에 적용했다(완료 17:01:23 KST). 실행 시 사전 조건을 다시 검사하고 검증 실패 시 전체 rollback하도록 구성했다. 기록된 SQL은 저장소 원본과 일치한다.
- 사후 검사(17:03:41 KST): 추가 이력은 `20261113090000` 한 개뿐이고 기존 이력 삭제는 없다. 표·세 함수 존재, 표 RLS 활성화, anon/authenticated 직접 SELECT 불가를 확인했다. 기존 Storage 공개 정책은 전후 해시가 모두 같았다.
- anon 실행 권한은 `oi_nfc_postcard(text)` **true**, `oi_operator_set_nfc_tag(text,uuid,boolean,text)`·`oi_operator_nfc_tags()` **false**다. `BEGIN READ ONLY` 안에서 실제 anon 역할의 `oi_nfc_postcard('no-such-tag') IS NULL`과 태그 **0건**을 검사한 뒤 `ROLLBACK`했다.
- CLI `--read-only` 계정은 사용자 정의 함수 실행이 제한되고 SET 문도 허용하지 않아 최초 함수 호출 검사가 거절됐다. 위 SQL 읽기 전용 트랜잭션으로 분리해 통과했으며, 적용 트랜잭션 실패나 추가 변경은 없었다.
- 다른 미적용 파일 `20261111101610_oi_bounded_collection_metrics.sql`은 **적용하지 않았다**. 실제 태그 연결·이야기·계정·공개 상태를 만들거나 변경하지 않았고, 가상 자료 삽입 검사도 실행하지 않았다. 실기기 NFC 호출과 운영 데이터의 엽서 표시 확인은 남아 있다.
