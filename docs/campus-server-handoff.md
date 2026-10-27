# 캠퍼스 오이 공유 서버 — 배포 인계 (#96)

2026-10-27. `feat/#96-campus-geo-ar`에서 기존 `apps/web`(Next.js + PostgreSQL)을 확장했다. **코드와 임시 로컬 DB 검증이며, 운영 배포 완료가 아니다.**

## 기존 돗자리 DB에 관해 확인한 것

`.railway/railway.ts`에 `benchmark-mat-pilot` 프로젝트, `Postgres` DB 서비스, `mat-web` 웹 서비스와 기존 환경변수 보존 설정이 있다. 이 Mac에서는 로그인된 Railway 계정·프로젝트 연결 정보·운영 URL을 찾지 못했다. 사용자가 팀원 소유 계정이라 접근할 수 없다고 확인했다. 이름은 저장소의 설정에서 확인했으며, 운영 리소스가 현재 존재하는지·가동 중인지·그 DB에 어떤 데이터가 있는지는 확인하지 못했다.

DB 비밀번호를 앱이나 채팅으로 전달할 필요는 없다. 소유 팀원이 아래 절차로 배포하고 **공개 HTTPS 주소만** 앱 담당자에게 전달하거나, 본인의 Railway 프로젝트에 별도 멤버로 초대할 수 있다. 팀원에게 메시지를 자동 발송하지 않았다.

## 구현한 연결

```text
운영진: 외부 증빙 검토 → /admin/campus에서 작성 승인 코드 발급
이용자: 앱에서 코드 등록 → 지도 바닥 선택 → 이름·제목·이야기 저장
서버: 소유권·캠퍼스 범위 검증 → pending 저장
운영진: 내용·위치 공개 검토 → published
모든 이용자: 공개 목록 → 같은 오이 ID·좌표 → 지도 / 현장 AR → 같은 이야기
```

- 기존 `mat_*` 테이블·예약·사진·반응 기능을 유지한다. `003_campus_ois.sql`은 `campus_writers`, `campus_ois`, `campus_reviews`만 추가한다.
- 공개 콘텐츠는 로그인을 요구하지 않는다. 글을 쓰려면 운영자가 발급한 256bit 난수 코드를 한 번 교환한다. 서버는 코드·토큰 해시만 저장하고, 앱은 토큰을 서버 origin별 Keychain에 저장한다. API는 관리자 쿠키가 아닌 Bearer 토큰을 사용한다.
- 신규 저장과 수정은 모두 `pending`이다. 작성자만 자신의 글을 읽거나 수정·삭제할 수 있고, 운영자가 공개해야 다른 이용자에게 표시된다. 게시물 공개 검토는 이번 파일럿의 구현 방식이며 최종 운영 정책으로 확정한 것이 아니다.
- 코드 등록 기한 24시간·토큰 30일은 파일럿 기술 기본값이다. 기부금/승인 수량 정책이 아니다. 운영진이 **같은 작성 권한 ID로 재발급**하면 기존 글 소유권은 유지하고 이전 코드·토큰을 무효화한다. 새 코드를 잃은 경우에도 같은 ID에서 재발급한다. 취소된 권한은 재발급으로 복구하지 않는다.
- 권한 취소 시 쓰기를 거절하고 해당 작성자의 공개 조회를 중단한다. 등록 코드 재사용은 원자적으로 차단한다. POST는 클라이언트 UUID·내용 해시로 동일 요청 재시도를 처리하고, 수정/삭제/공개는 revision으로 동시 덮어쓰기를 거절한다.
- 원문 증빙·계좌·학교 납입 상태를 새 테이블에 저장하지 않는다. 이번 범위는 **외부에서 검토한 결과의 글 작성 권한**이며 증빙 접수 시스템이나 학교 공식 기부 확인 API가 아니다.
- 운영자 인증은 기존 공유 비밀번호를 재사용한다. 감사 기록의 처리자는 `shared-admin`이다. 담당자별 실명 감사·계정 로그인은 아직 없다. 실제 자료 수집 방식·담당자 식별·보관 정책은 운영 전에 별도 확정해야 한다.

## 캠퍼스 범위 및 AR 한계

학술정보관 150m 반경으로 제한하지 않는다. 현재 앱에 포함된 POSTECH 지도 데이터의 경계 폴리곤 3개 안에서 건물 평면을 제외한다. 이는 모델에 정의된 캠퍼스 범위이며 학교의 모든 부지·실제 출입 가능성을 보증하지 않는다. 위치 공개 전에 운영진이 실제 이용 가능한 공간인지 검토한다.

`campus-data.json`의 WGS84 ENU 원점·축척·경계·건물 좌표와 서버의 `campus-geometry.json`을 비교하는 테스트가 있다. 원본 지도를 바꾸면 `npm run campus:geometry -w apps/web`로 서버 파일을 갱신하고 테스트한다. 모델 지형 높이를 AR 지리 고도로 저장하지 않는다.

공용 DB가 같으면 ID·위도·경도·크기·방향·이야기가 같아진다. 그러나 기기마다 GPS/나침반/지리 추적 상태가 달라 **현실에서 센티미터 단위로 같은 위치에 고정되는 것은 아니다.** POSTECH 현장의 ARGeoTracking 지원과 위치 오차는 실기기 검증이 필요하다. 일반 사진·손바닥 AR은 기존 카메라에 유지한다. 새 위치 AR은 오이 선택·이야기 확인 기능이며 사진 촬영을 새로 통합하지 않았다.

## 소유 팀원의 배포 순서

1. 실제 Railway 프로젝트가 `benchmark-mat-pilot`인지, 현재 웹 서비스와 DB가 연결돼 있는지 확인한다. 운영 데이터 백업을 확보한다. 설정 파일로 새 프로젝트/DB를 생성하거나 기존 DB를 초기화하지 않는다.
2. 리뷰된 이 브랜치의 `apps/web`, `database`, `Dockerfile`, 루트 package 파일을 포함한 소스를 기존 `mat-web`에 배포한다. 루트 Dockerfile을 사용한다. **미병합 PR #93 기반 브랜치**이므로 병합 순서와 충돌을 확인하고, 자동 배포 브랜치를 임의 변경하지 않는다.
3. 기존 `DATABASE_URL`, `ADMIN_PASSWORD`, `SESSION_SECRET`을 유지한다. `APP_ORIGIN`은 실제 공개 HTTPS origin(경로·마지막 `/` 제외)과 일치시킨다. 다른 기존 기부 안내 환경변수는 변경하지 않는다.
4. 배포 전 명령 `npm run db:migrate`를 실행한다. 기존 migration 이력과 advisory lock을 사용하며, 003만 추가 적용한다. 실패하면 배포를 진행하지 않고 로그를 확인한다. 운영 DB에 테스트 명령이나 DELETE/TRUNCATE를 실행하지 않는다.
5. `GET /api/health`가 성공하고 `GET /api/campus/ois`가 `{ "items": [], "nextCursor": null }` 또는 실제 공개 목록을 반환하는지 확인한다. 후자의 응답은 003 적용 여부도 확인한다.
6. `/admin/campus`에서 기존 관리자 비밀번호로 로그인한다. 가상 자료로 작성 코드 등록→비공개 저장→공개→다른 기기 조회→비공개/취소를 먼저 검증한다. 실제 이용자에게 코드를 발급하기 전에 운영 기준을 확정한다.
7. 앱 담당자에게 **실제 웹 서비스의 공개 HTTPS origin**을 전달한다. `DATABASE_URL`·관리자 비밀번호·세션 비밀키를 앱에 넣지 않는다.

롤백이 필요하면 이전 웹 빌드로 복귀하고 새 테이블은 보존한다. 이미 저장된 캠퍼스 콘텐츠를 삭제하는 역방향 migration은 제공하지 않는다. 이전 API는 새 테이블을 참조하지 않는다.

## iOS 주소 설정과 이용 흐름

`OiDonation` 타깃의 Debug/Release Build Settings → User-Defined에 `OI_CAMPUS_API_ORIGIN`을 추가하고 실제 `https://호스트` 값을 넣는다. `Configuration/OiDonation-Info.plist`에서 확장된다. 이 설정은 서명 Team·Bundle ID·프로비저닝과 별개다. 기본값은 비어 있으며 확인하지 않은 URL은 커밋하지 않았다.

로컬 빌드에서만 지정할 수도 있다(아래 도메인은 형식 예시):

```sh
xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiDonation \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO \
  OI_CAMPUS_API_ORIGIN=https://your-confirmed-host.example build
```

- 홈 기본 모드는 **공유 캠퍼스**다. 주소 미설정은 연결 대기로 표시하고, 공개 API 오류를 기기 예시로 대체하지 않는다.
- 우측 메뉴의 **기기 예시 테스트**는 종전의 로컬 예시 저장이다. 실제 승인·공용 데이터와 섞지 않는다.
- 작성 코드 등록 → 오이 심기 → 지도에서 위치 선택 → 키/방향 → 이야기 작성 → 저장. `오이 목록 → 내가 쓴 오이`에서 검토 상태·수정·삭제를 확인한다.
- 운영자가 공개한 오이는 모든 이용자의 지도/공개 목록에 나타난다. 지도에서 탭해 이야기를 읽고 ‘현장에서 AR로 보기’로 진입한다. AR은 진입 시와 표시 중 30초 간격으로 공개 여부·좌표를 재확인한다. 삭제/비공개/통신 실패 시 렌더링을 중단한다.
- 지도는 활성 상태에서 약 30초마다 새로고침하며 목록에서 수동 갱신할 수 있다. 푸시나 실시간 소켓 동기화가 아니다. 이야기 상세는 진입할 때 서버에서 다시 조회한다.
- 첫 범위는 텍스트 이야기·공개 이름·위치·크기·방향, 안전모 오이 모델 하나다. 이미지 업로드, 캐릭터 종류/꾸미기, 계정 기반 수집은 후속 범위다. App Clip에는 이번 API/UI를 연결하지 않았다.

## API 계약 요약

| 경로 | 권한 / 처리 |
| --- | --- |
| `GET /api/campus/ois` | 공개 목록. `cursor` UUID, 선택적 `south/west/north/east`, 페이지당 200개 |
| `GET /api/campus/ois/:id` | 공개 글 또는 유효한 작성자 토큰의 자기 글 |
| `POST /api/campus/session` | `{code}` 교환, `{writerID,token,expiresAt}` 반환. 재사용·만료 거절 |
| `GET /api/campus/mine` | Bearer, 자기 글 모든 상태, cursor 페이지 |
| `POST /api/campus/ois` | Bearer, 새 UUID·좌표·이름·제목·본문, pending |
| `PUT /api/campus/ois/:id` | Bearer 소유자, 전체 내용+revision, pending으로 재검토 |
| `DELETE /api/campus/ois/:id` | Bearer 소유자, `{revision}` |
| `/api/admin/campus/grants` | 관리자 쿠키: 목록/발급. POST `{reviewConfirmed:true,writerID?:UUID}` |
| `DELETE /api/admin/campus/grants/:id` | 관리자 쿠키+Origin, 작성 권한 취소·공개 중단 |
| `GET /api/admin/campus/ois` | 관리자 목록 |
| `PUT /api/admin/campus/ois/:id` | 관리자 쿠키+Origin, `{status:"published" 또는 "hidden",revision}` |

등록 내용: `id`, `campusID:"postech"`, `model:"helmet-oi"`, `latitude`, `longitude`, `heightMeters`(0.4~2), `headingDegrees`(0~360 미만), `displayName`(40 UTF-16 단위 이하), `title`(80), `story`(2000). 응답의 `storyID`는 오이 ID와 동일하다. 서버가 소유자를 결정하며 요청의 status/owner 필드는 거절한다. 공개 응답에 인증·승인 코드·증빙은 없다.

## 검증 및 남은 작업

- iOS Simulator 컴파일 및 Info.plist 주소 주입 확인. 기존 좌표 2,081개 왕복·기기 저장·이야기·라우팅 검사 통과.
- Swift 클라이언트 가상 HTTP: HTTPS origin, 페이지 합치기, 잘못된 공개 데이터·반복 cursor·인증/숨김 오류·ID 일치 검사.
- 웹 lint/typecheck, 단위 테스트, 격리 PostgreSQL 18 migration + 실제 HTTP 통합 테스트. 다른 클라이언트 동일 콘텐츠, 코드 단일 사용, 소유권, 공개, 동시 수정, 삭제, 재발급, 만료·취소, 200개 초과 페이지 확인. 기존 돗자리 API 통합 테스트도 포함.
- 운영자 브라우저 검증: 로그인, 증빙 확인 전 코드 발급 금지, 코드 발급·앱 등록, 공개 전 익명 404, 공개 후 200, 숨김 후 404 및 모바일/데스크톱 가로 넘침 검사 통과.
- npm 운영 의존성 보안 알림에 따라 Next.js/eslint-config-next 16.4.3, sharp 0.35.5, zod 4.6.7 및 source-map-js를 갱신했다. 확인 당시 `npm audit --omit=dev` 알림 0개.
- **미완료:** 팀원 계정의 실제 Railway 상태·운영 배포·공개 URL, 두 실제 iPhone 공유 지도/AR 확인, 현장 정확도·대량 3D 모델 성능, 운영 정책/증빙 검토 절차 확정.
