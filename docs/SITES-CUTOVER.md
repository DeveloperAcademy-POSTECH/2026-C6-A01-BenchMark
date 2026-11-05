# Sites 전환 검증 기록 — #76

## 결과 — 2026-10-26

기존 Railway 웹·DB의 실행 의존성을 제거하고 기존 Sites 배포를 사용하도록 전환했다. 원본 DB를 읽기 전용으로 대조하고 누락된 활동 로그 4건을 추가했다. 기존 웹 쓰기를 중단한 뒤 마지막 원본 대조에서도 누락·변경 충돌이 없었다. BenchMark production·design-preview의 활성 배포가 모두 없는 것을 확인했다. 원본 볼륨은 삭제하지 않았다.

파일럿·팀 소개는 사용자 요청으로 **소유자 전용 유지**, 오이기부는 기존 공개 범위를 유지했다. 따라서 파일럿의 익명 요청 401은 선택한 접근 정책의 정상 동작이다.

| 서비스 | 저장소 소스 | Sites ID | URL |
| --- | --- | --- | --- |
| 돗자리 파일럿 | apps/web | appgprj_6acf2f2aba648191a53e08da88cf1bb2 | https://benchmark-pilot.deep-chime-2567.chatgpt.site |
| 오이기부 | apps/oi-web | appgprj_6acf33605044819182d185f849dcc0d6 | https://oi-donation.deep-chime-2567.chatgpt.site |
| 팀 소개 | apps/team-web | appgprj_6acf3351f814819199fc2ee2a2c0e895 | https://benchmark-team.deep-chime-2567.chatgpt.site/benchmark |

## 원인

이전 #76은 검증 환경을 만들고 Railway를 계속 실행하는 범위였다. Sites 배포 소스와 GitHub develop의 PostgreSQL/Railway 소스·CI·문서가 분리되어 있었다. 이번 변경은 실제 Sites 소스를 팀 저장소에 반영하고 SDK·Docker·Railway 배포 정의와 기존 PostgreSQL CI를 제거한다. 기존 UUID·사진·로그·권한·화면 동작은 배포 소스를 기준으로 보존한다.

## 원본 데이터 대조

원본 PostgreSQL은 REPEATABLE READ READ ONLY 트랜잭션으로 읽었다. 타임스탬프는 ISO 밀리초로 정규화하고 객체 키·행 순서를 정렬했다. 사진은 SHA-256으로 비교한다. 다음은 마지막 대조 결과이며 원본 내용·개인정보·접근 토큰은 기록하지 않는다.

| 항목 | 원본 | Sites | 누락/충돌 | 정규화한 원본 SHA-256 |
| --- | ---: | ---: | --- | --- |
| mat_stories | 21 | 21 | 0 / 0 | d48aff2b68e3208aa1586638deddfe505547ecebe319ddc8ddf183f74f6a410a |
| mat_reservations | 0 | 0 | 0 / 0 | 4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945 |
| mat_reactions | 29 | 29 | 0 / 0 | 371cb6324bc3666d70a802a83bcaec10ca14c632393c07b541da2a2d02a1cb56 |
| mat_activity_events | 28 | 2119 | 0 / 0 | f796b0927c2fa6717d5308b822d3d4398e5a778253b1e7b269a75c582b113c18 |
| schema_migrations | 9 | 9 | 0 / 0 | 182708c47d1cec4de40af1797879140a774d424f920040cb2942c5a2a8977cf3 |

이야기·예약·반응·스키마 이력은 양쪽 전체 해시도 일치했다. 활동 로그는 원본 28건이 전부 Sites에 동일하게 존재하며 Sites에만 있던 2,091건도 보존했다. 기록 보관기간 처리는 기존 앱 정책을 따른다. 공개 사진 21개의 실제 HTTP 응답도 R2 사진 해시와 모두 일치했다.

## 검증

- 세 앱 TypeScript 검사·Worker 빌드 통과.
- 파일럿 단위·D1/R2 테스트 27개 통과.
- 로컬 Worker HTTP 통합 테스트 통과: 인증, 예약 전환, 중복 등록, revision 충돌, 사진 접근, 반응 동시성, CSV, 삭제.
- 실제 Sites 검증 통과: 원본 관리자 비밀번호 로그인, 예약·실제 Netlify 사진 변환, 사진 접근 통제, 같은 예약 재시도, 예약의 이야기 등록, 반응 동시 요청, revision 충돌, CSV, 예약 삭제 시 이야기 보존.
- 실제 검증에는 합성 fixture만 사용했고 만든 예약·이야기는 모두 삭제했다. 실제 사용자의 기부·납입 증거로 취급하지 않는다.
- 파일럿 `/stories`, `/reserve`, `/admin`, `/api/health` 200. 오이기부 공개 페이지와 Sites 간 이동, 팀 소개 `/benchmark` 200.
- 마지막 배포: version 8, source `32d1a7e0f9fd8f0d903efba0c16bd7ec3f8c90f1`, deployment `appgdep_6adf07a555108191adf0c0e8cd37e8ea`, status `succeeded`, environment revision 7.
- `MIGRATION_ENABLED=false`, 임시 `MIGRATION_TOKEN` 제거 후 `/api/migration`의 404 확인.
- 원본 조회용 임시 SSH 키 등록을 제거하고 로컬 키 파일·SSH 터널·검증 서버도 정리했다.

## 남은 외부 제한

**Needs confirmation: Google 로그인 제공자 복구.** 기존 Railway와 Android, Sites가 모두 `kfzfzarslqdqmrazohej.supabase.co`를 사용한다. 실제 Google 로그인 버튼은 이 주소로 PKCE 요청을 만들지만 DNS 조회가 ENOTFOUND/NXDOMAIN으로 실패한다. 연결된 Supabase 계정에는 해당 프로젝트가 없고 프로젝트 조회도 권한 오류다. 원본과 동일한 장애이며 Sites에서 Google 로그인 완료를 주장하지 않는다. 프로젝트 소유자가 기존 프로젝트를 복구하거나 올바른 프로젝트 접근 권한을 제공해야 한다. 임의로 다른 프로젝트로 연결하지 않는다.

사진 변환은 기존 서명된 Netlify 함수를 유지한다. 실제 배포에서 성공을 확인했으며 Railway에 의존하지 않는다. 모든 외부 기능이 Sites 내부에 있는 구조는 아니다.

Railway 소유의 `*.up.railway.app` 주소는 서비스 중단 후 유지할 수 없다. 기존 이야기 UUID와 경로는 Sites에 보존했지만 해당 옛 도메인을 담은 QR/NFC·외부 링크는 Sites 주소로 갱신해야 한다. 저장소 밖의 실물 태그가 변경됐다고 주장하지 않는다.
