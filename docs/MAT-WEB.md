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

공개 이름은 필수다. 예약 제목은 1~80자이며 기존 제목 없는 이야기는 이름으로 대체 제목을 표시한다. 본문은 UTF-8 기준 1000바이트 이내다. 한글은 보통 3바이트, 이모지는 4바이트다. 사진은 JPG/PNG/WebP 정지 이미지 한 장, 5MB 이하이며 실제 디코딩 후 긴 변 1600px 이하 JPEG로 저장한다. 방향을 보정하고 메타데이터를 제거한다.

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

`003_story_byte_limit.sql`은 기존 이야기와 예약 본문을 보존하면서 두 테이블의 본문 제약을 1000바이트로 확대한다. 새 앱 배포 전에 적용한다. 500바이트를 초과하는 본문이 저장된 이후에는 데이터 확인 없이 이전 제약으로 되돌릴 수 없다.

필수 환경변수는 DATABASE_URL, ADMIN_PASSWORD(9자 이상), SESSION_SECRET(무작위 32자 이상), APP_ORIGIN이다. 기존 DONATION_* 변수는 유지하지만 예약 전용 화면에서는 계좌를 표시하지 않는다. SESSION_SECRET을 변경하면 반응 식별자 연결이 끊기므로 비밀번호 변경과 별도로 관리한다. 도메인 변경 시 APP_ORIGIN도 변경한다.

## 디자인 근거

- Figma 파일: `nEDJaJBFrdzBCa1WcgADHH`
- `178:584`: 597×1578 기준 이야기 프레임. 로고 → 제목·사진·본문 카드 → 반응 4열 → 사용 안내 → 예약 CTA 순서를 적용한다.
- `178:595`: 예약 이유 → 이름·휴대폰 → 제목·본문·사진 → 결제방법 → 금액 → 제출 순서를 적용한다.
- 기존 종이색·녹색·갈색 테마, 이서윤체, 타이틀 SVG 및 `172:567`·`172:568` 크기 라벨은 유지한다. 회색 lo-fi 박스와 예시 이름·사진은 실제 디자인이나 운영 데이터로 사용하지 않는다.
- 반응 아이콘은 Figma `195:629`·`195:633`·`195:637`·`195:642` 원본 렌더를 사용한다.
- 고정 높이 대신 콘텐츠 길이에 따라 확장한다. 모바일에서는 여백을 줄이고 반응 4열·결제방법 3열을 유지한다. 독서와 입력 화면은 넓은 화면에서도 읽기 좋은 최대 너비를 둔다.
