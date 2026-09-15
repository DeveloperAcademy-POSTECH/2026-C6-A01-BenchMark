# 쉼, 펴 — 돗자리 파일럿 웹

2026-09-15 확정된 요구사항과 Figma lo-fi를 반영한다. 돗자리 목표는 100개다. 네이버 폼은 병행하지 않으며 웹에서 기부 예약을 직접 접수한다.

## 사용자 흐름

- `/`: 첫 공개 이야기의 제목·사진·본문 → 네 가지 반응 → 사용 안내 → 기부 예약 안내
- `/stories`: 전체 공개 이야기 목록
- `/stories/:id`: 기존 고정 주소로 제목·사진·본문 → 네 가지 반응 → 사용 안내 → 기부 예약
- `/reserve?from=:id`: 예약 이유·성함·휴대폰번호·제목·본문·사진·희망 결제방법·자유 금액 입력
- `/about`: 별도 소개 화면 없이 메인 `/`으로 영구 이동
- `/admin`: 페이지 하단 링크 → 공유 비밀번호 → 예약 접수함 및 이야기 관리

예약은 결제가 아니다. 결제방법은 무통장입금·간편결제·계좌이체 중 희망하는 방법을 기록하며 PG나 간편결제 API를 실행하지 않는다. 금액은 1원 이상 원 단위 정수로 자유 입력한다. 접수 후 운영진이 연락한다. 개인정보 수집 안내·동의 UI는 사용자 요청으로 생략했다.

공개 이름은 필수다. 예약 제목은 1~80자이며 기존 제목 없는 이야기는 이름으로 대체 제목을 표시한다. 본문은 UTF-8 기준 500바이트 이내다. 한글은 보통 3바이트, 이모지는 4바이트다. 사진은 JPG/PNG/WebP 정지 이미지 한 장, 5MB 이하이며 실제 디코딩 후 긴 변 1600px 이하 JPEG로 저장한다. 방향을 보정하고 메타데이터를 제거한다.

## 운영

1. 관리자 접수함에서 예약 금액·이유·휴대폰·희망 결제방법·이야기·사진을 확인한다.
2. 기부 진행을 안내한 뒤 ‘이 예약으로 이야기 등록’을 누른다. 이름·제목·본문·사진은 자동으로 채워진다.
3. 돗자리 번호와 크기를 배정하고 실제 입금을 별도로 확인한다. 예약 금액만으로 입금 완료 처리하지 않는다.
4. 공개 내용을 검토하고 ‘입금 확인 완료’ 및 ‘내용 검토 완료 · 웹에 공개’를 선택한다.
5. 이미 등록한 예약은 중복으로 이야기 등록할 수 없다. 이후 수정은 이야기 목록에서 한다.
6. 예약 삭제는 휴대폰 등 예약 자료와 예약 사진을 제거한다. 이미 등록한 이야기는 유지한다. 이야기 삭제는 이야기·공개 사진·반응을 제거한다.
7. 수정 시 기존 이야기 주소를 유지한다. 비공개 전환 시 사진도 비공개로 전환한다.

같은 이야기를 여러 관리자가 수정하면 revision 비교로 덮어쓰기를 막는다. 예약의 이야기 등록은 행 잠금과 트랜잭션으로 중복을 막는다. 공유 비밀번호 방식이므로 개별 관리자 신원은 식별하지 않는다. 종료일·QR 생성·도메인 구매는 별도 운영 단계다.

## 저장과 요청 검증

Next.js App Router / React / TypeScript, PostgreSQL, sharp를 사용한다. 이야기와 예약 사진은 PostgreSQL에 저장한다. Railway 임시 파일시스템을 저장소로 사용하지 않는다.

- 예약 연락처·이유·결제방법·금액은 관리자에게만 반환한다. 예약 사진 API도 관리자 인증을 요구한다.
- 공개 조회는 입금 확인과 공개 승인이 모두 있는 이야기만 반환한다. 사진 응답은 `private, no-store`다.
- 네 반응은 종류별 한 번씩 선택 가능하고 취소는 하지 않는다. localStorage UUID를 HMAC으로 변환한 `(story_id, device_hash, kind)` 고유 키로 중복을 막는다.
- 기존 공감 기록은 `empathy`로 유지한다. 브라우저 저장소 삭제·시크릿 모드·다른 브라우저는 별도 식별자가 된다.
- 예약 재시도는 요청 UUID로 중복을 막으며, 같은 UUID의 다른 내용은 충돌로 반환한다. 입력을 바꾸면 새 UUID를 사용한다.
- 세션은 8시간, HttpOnly·SameSite=Strict이며 production에서는 Secure 쿠키다. 비밀번호 변경 시 기존 세션도 무효화된다.
- 변경 요청은 `APP_ORIGIN`과 Origin을 비교한다. 로그인과 예약은 각각 IP 해시별 15분당 10회 및 전체 100회로 제한한다. 반응 쓰기는 식별자별 분당 100회다.
- 비밀번호·휴대폰·사진·이야기는 서버 로그에 출력하지 않는다.

## 로컬 실행

Node 24~26과 PostgreSQL이 필요하다. 저장소 루트에서 실행한다.

```bash
npm ci
cp .env.example .env
# DATABASE_URL, ADMIN_PASSWORD(9자 이상), SESSION_SECRET(32자 이상), APP_ORIGIN 설정
node --env-file=.env --import tsx apps/web/scripts/migrate.ts
node --env-file=.env node_modules/next/dist/bin/next dev apps/web
```

환경 파일은 Git에 포함하지 않는다. APP_ORIGIN은 실제 접속 origin과 일치시킨다.

## 검증

```bash
npm run lint
npm run typecheck
npm test
npm run build
node --env-file=.env.test --import tsx apps/web/scripts/migrate.ts
node --env-file=.env.test node_modules/next/dist/bin/next start apps/web --hostname 127.0.0.1 --port 4314
# 다른 터미널
node --env-file=.env.test --import tsx --test apps/web/tests/api.integration.ts apps/web/tests/reservation.integration.ts
cd apps/web
node --env-file=../../.env.test ../../node_modules/@playwright/test/cli.js test
```

통합 검증은 전용 `benchmark_mat_test` DB만 허용한다. `.env.test`에는 DATABASE_URL·ADMIN_PASSWORD·SESSION_SECRET·APP_ORIGIN·TEST_BASE_URL을 설정한다. 테스트 origin은 `http://127.0.0.1:4314`다. Chrome은 headless로 실행하고 필요하면 CHROME_EXECUTABLE을 지정한다.

검증 범위는 UTF-8 경계, 인증, 공개 조건, 사진 검증, 예약 동시 재시도, 등록 중복, 반응 네 종류 동시 요청, 수정 충돌, 삭제, 모바일 예약·오류·재시도 흐름이다. screenshots의 자료는 검증용 콘텐츠이며 실제 기부자나 현장 사용 증거가 아니다.

## Railway 배포

웹 서비스와 PostgreSQL 서비스 두 개를 사용한다. 기존 Dockerfile과 `.railway/railway.ts`를 유지한다. 배포 전 `npm run db:migrate`와 `/api/health` 상태 검사를 수행한다.

`002_reservations_and_reactions.sql`은 기존 이야기 ID와 사진을 유지하고 제목·새 본문 제약·반응 종류·예약 테이블을 추가한다. 기존 100자 본문은 최대 400바이트이므로 500바이트 제약 안에 들어간다. 기존 API의 종류 없는 반응 요청은 공감해요로 처리해 배포 전후 클라이언트와 호환한다. 마이그레이션은 트랜잭션과 이력 테이블로 한 번만 적용한다. 운영에서 신규 예약·반응이 생긴 뒤 옛 스키마로 되돌리는 파괴적 롤백은 제공하지 않는다.

필수 환경변수는 DATABASE_URL, ADMIN_PASSWORD(9자 이상), SESSION_SECRET(무작위 32자 이상), APP_ORIGIN이다. 기존 DONATION_* 변수는 유지하지만 예약 전용 화면에서는 계좌를 표시하지 않는다. SESSION_SECRET을 변경하면 반응 식별자 연결이 끊기므로 비밀번호 변경과 별도로 관리한다. 도메인 변경 시 APP_ORIGIN도 변경한다.

## 디자인 근거

- Figma 파일: `nEDJaJBFrdzBCa1WcgADHH`
- `178:584`: 597×1578 기준 이야기 프레임. 로고 → 제목·사진·본문 카드 → 반응 4열 → 사용 안내 → 예약 CTA 순서를 적용한다.
- `178:595`: 예약 이유 → 이름·휴대폰 → 제목·본문·사진 → 결제방법 → 금액 → 제출 순서를 적용한다.
- 기존 종이색·녹색·갈색 테마, 이서윤체, 타이틀 SVG 및 `172:567`·`172:568` 크기 라벨은 유지한다. 회색 lo-fi 박스와 예시 이름·사진은 실제 디자인이나 운영 데이터로 사용하지 않는다.
- 반응 아이콘은 Figma `195:629`·`195:633`·`195:637`·`195:642` 원본 렌더를 사용한다.
- 고정 높이 대신 콘텐츠 길이에 따라 확장한다. 모바일에서는 여백을 줄이고 반응 4열·결제방법 3열을 유지한다. 독서와 입력 화면은 넓은 화면에서도 읽기 좋은 최대 너비를 둔다.

## 페이지 활동 로그 (#11)

사용자 결정에 따라 분석 동의 UI 없이 공개 페이지의 활동을 PostgreSQL에 수집한다. 별도 유료 분석 도구·세션 녹화는 사용하지 않는다. 관리자 `/admin`의 **페이지 활동 로그**에서 시작/종료 시각(종료 미포함), 이벤트, 페이지 경로, 스토리 UUID를 조합해 조회하고 **현재 조건으로 CSV 저장**할 수 있다. 조회는 최신순 100건씩이며 다음 페이지는 시각+이벤트 ID 커서로 이동한다. CSV는 현재 입력한 필터 전체 결과를 최대 5,000건까지 저장한다. 초과 시 기간/필터를 좁히도록 오류를 표시하고 일부만 저장하지 않는다. 화면 시간은 브라우저 현지 시간이고 CSV는 UTC다.

| 이벤트 | 기준 / 허용 속성 |
| --- | --- |
| `page_view` | 공개 페이지 방문당 한 번. 새로고침·뒤로 가기는 새 방문, React 재렌더링은 같은 방문 |
| `scroll_depth` | 문서 높이 대비 화면 하단의 도달률 25/50/75/100%를 방문당 한 번씩. 최초 화면에 이미 보이는 구간 포함 |
| `active_time` | visible이며 포커스가 있는 동안의 체류 시간 `milliseconds`. 약 15초마다 차분을 저장하고 숨김·포커스 이탈·페이지 이동 시 정산 |
| `link_click` | 실제 존재하는 홈/이야기 목록/이야기 상세/예약/카메라 링크 클릭. `target`, 상세 링크의 `targetStoryId`만 기록 |
| `reaction_attempt/success/failure` | 반응 요청 직전/성공 응답/실패. `kind`는 like/empathy/sad/cheer 중 하나 |
| `reservation_attempt/success/failure` | 클라이언트 입력 검증을 통과한 예약 제출 요청/접수 응답/실패. 예약은 실제 결제·기부 완료가 아님 |
| `photo_selected` | 예약에서 사진 파일을 선택한 사실만 기록. 파일명·사진·미리보기는 수집하지 않음 |

공통 필드는 이벤트 UUID, 방문 UUID, 탭 세션 UUID, 이벤트명, 클라이언트 발생 시각, 서버 수신 시각, 쿼리 없는 공개 경로, 해당 페이지의 스토리 UUID, 허용 속성이다. 메인에는 실제 표시한 스토리, 예약에는 서버가 UUID로 검증한 `from`을 연결한다. 기록할 스토리는 서버에서 현재 공개 여부를 검증한다. 관리자 페이지·예약 입력 내용·이름·연락처·본문·사진·인증정보·전체 URL·referrer·임의 속성은 수집하지 않는다. 최신 develop에 통합된 `/camera`는 진입 스토리 UUID를 이어받으며 `camera_start_attempt/ready/failure/switch/stop/retake`, `photo_capture_attempt/success/failure/cancelled`, `photo_share_attempt/success/failure/cancelled/unavailable`, `photo_download_click`을 별도 수집한다. 공유 성공은 Web Share API 완료이고 수신자의 열람을 뜻하지 않는다. 다운로드 클릭은 파일이 실제 저장됐다는 증거가 아니다. 카메라 영상·촬영 사진·파일명·오류 원문은 기록하지 않는다.

세션은 탭 메모리와 sessionStorage를 사용하며 새 탭/브라우저는 새 세션이다. 새로고침은 30분 이내의 같은 탭 세션을 재사용한다. 포인터·키보드·스크롤·포커스 복귀 등 사용자의 동작이 30분 이상 없으면 다음 동작 시 새 세션/방문을 시작한다. 자동 체류 전송은 세션 활동 시각을 연장하지 않는다. 저장소가 차단되면 메모리 세션으로 동작한다. 사용자 계정·기존 반응 device ID와 결합하지 않으며 날짜를 넘긴 고유 사용자/장기 재방문 지표를 제공하지 않는다.

전송은 5초 간격, 최대 20건/16KiB, 메모리 대기열 100건, 요청 제한시간 4초, 이벤트당 최대 3회다. 재시도는 같은 이벤트 ID를 유지한다. DB의 이벤트 ID 고유 키와 방문별 조회/스크롤 구간 고유 인덱스로 중복을 제거한다. 페이지 이탈 시 keepalive로 마지막 전송을 시도한다. 네트워크 단절·탭 강제 종료·한도 초과 시 로그가 유실될 수 있으며 원래 반응·예약 기능은 계속 동작한다. 체류 시간은 브라우저 정지/슬립으로 부풀리지 않도록 각 타이머 구간을 최대 15초로 제한하므로 심한 타이머 지연 때는 과소 집계될 수 있다. 로그는 클라이언트가 보고한 행동이며 사람의 실제 독서나 기부를 증명하지 않는다.

### 로그 권한·보관·운영

- `POST /api/activity`: 동일 Origin만 허용, 전체 분당 600요청·세션당 120요청, 엄격한 이벤트/속성 검증, 최대 24시간 전~1분 후 발생 시각만 허용한다. 요청의 원문이나 오류 payload를 서버 콘솔에 출력하지 않는다. 공개 수집 API이므로 자동화된 허위 이벤트를 완전히 배제할 수는 없다.
- `GET /api/admin/activity`: 기존 관리자 세션 인증 및 분당 60요청 제한을 적용한다. 미인증 JSON/CSV 요청을 모두 차단하고 `private, no-store`로 반환한다. 공유 관리자 비밀번호이므로 개별 조회자 신원은 구분하지 않는다.
- `003_page_activity.sql`은 기존 데이터 변경 없이 로그 테이블과 인덱스를 추가하고 `004_camera_activity.sql`은 카메라 이벤트 허용 목록을 확장한다. 운영 배포는 별도 수행하며 이 작업에서 운영 DB는 변경하지 않는다.
- 발생 시각 기준 30일이 지난 로그는 즉시 조회/다운로드 대상에서 제외한다. Node 서버 시작 시와 실행 중 매시간 자동 삭제한다. 따라서 디스크에서의 실제 제거는 서버가 실행 중일 때 최대 약 1시간 늦을 수 있고, 서버 중단 중에는 다음 시작 시 제거된다. 삭제 실패 시 서버 로그 `Activity retention cleanup failed.`를 확인한다.
- 즉시 정리가 필요하면 운영자가 DB에서 `DELETE FROM mat_activity_events WHERE occurred_at <= now() - interval '30 days';`를 실행한다. 전체 로그 제거는 `DELETE FROM mat_activity_events;`이며 되돌릴 수 없으므로 정확한 환경과 삭제 범위를 확인한다.
- 내려받은 CSV와 DB 백업은 서버 자동 삭제 대상이 아니다. 다운로드한 관리자가 동일한 보관 정책에 따라 별도로 삭제한다. 이야기 삭제 후에도 30일 동안 기존 스토리 UUID가 로그에 남지만 이름·본문·사진은 없다.

검증 추가: `npm test`의 입력/개인정보/CSV 단위 테스트, `npm run test:integration`의 실제 DB 중복·권한·필터·보관 테스트, Playwright `activity.spec.ts`의 재전송·페이지 이동·비활성 생명주기·관리자 조회/다운로드를 사용한다. 비활성 테스트는 headless 문서의 visibility 이벤트를 제어한 검증이며 실제 모바일 OS 백그라운드 실험과는 구분한다.
