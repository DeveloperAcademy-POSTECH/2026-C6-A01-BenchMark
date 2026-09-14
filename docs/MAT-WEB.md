# 쉼, 펴 — 돗자리 파일럿 웹

2026-09-14 확정 요구사항을 구현한다. 목표는 돗자리 100개이며 공개 예정 시각은 2026-09-16 20:00 KST다. 네이버 폼 접수는 유지하며 운영진이 내용을 수동 등록한다.

## 사용자 흐름

- `/`: 공개 이야기 목록, 추가 기부 안내
- `/stories/:id`: 돗자리별 고정 UUID 주소, 사진과 이야기, 공감
- `/about`: 프로젝트 소개, 2~3인용 3,000원 / 4~5인용 5,000원 안내, 입금 정보, 네이버 폼
- `/admin`: 페이지 하단 링크 → 공유 비밀번호 로그인 → 이야기 등록·검토

공개 이름은 필수이고 익명 등록은 지원하지 않는다. 사진은 JPG/PNG/WebP 정지 이미지 한 장, 5MB 이하이며 디코딩 후 긴 변 1600px 이하 JPEG로 저장한다. 방향을 보정하고 메타데이터를 제거한다. 이야기는 Unicode 코드 포인트 기준 100자 이내다.

## 운영

1. 네이버 폼 신청을 확인하고 이름·사진·이야기·돗자리 종류를 등록한다.
2. 실제 입금을 별도로 확인한 뒤 `입금 확인 완료`를 선택한다.
3. 공개 내용을 미리 보고 `내용 검토 완료 · 웹에 공개`를 선택해 저장한다.
4. 수정 시 기존 이야기 주소를 유지한다. 비공개 전환 시 사진도 비공개로 전환한다.
5. 삭제 시 해당 이야기·사진·공감이 함께 삭제되며 되돌릴 수 없다. UI에서 별도 확인을 받는다.

같은 이야기를 여러 관리자가 수정하면 revision 비교로 덮어쓰기를 막는다. 공유 비밀번호 방식이라 개별 작업자 신원은 식별하지 않는다. 종료일·모집 종료 스케줄·QR 생성은 이번 범위에 포함하지 않는다. QR은 도메인 확정 후 고정 이야기 주소로 제작한다.

## 저장과 보안

- Next.js App Router / React / TypeScript, PostgreSQL, `sharp`를 사용한다. PR #3의 공통 도구·DB 연결 구조를 참고하되 미병합 신청 기능을 포함하지 않는다.
- 이야기와 사진을 같은 PostgreSQL 레코드에 저장한다. Railway 컨테이너의 임시 파일시스템을 업로드 저장소로 사용하지 않는다.
- 공개 API는 입금 확인과 공개 승인이 모두 있는 이야기만 반환한다. 사진 응답은 `private, no-store`로 처리한다.
- 공감은 브라우저 localStorage UUID를 서버 HMAC으로 변환하고 `(story_id, device_hash)` 고유 키로 중복을 막는다. 공감은 취소 없이 한 번만 가능하다.
- **브라우저 저장소 삭제·시크릿 모드·다른 브라우저는 별도 식별자**가 된다. 물리 기기 전체를 식별하는 방식은 아니며, 지문 수집이나 계정을 추가하지 않는다.
- 관리자 비밀번호와 세션 서명 키는 서버 환경변수다. 클라이언트 번들에 포함하지 않는다. 세션은 8시간, HttpOnly·SameSite=Strict이며 production에서는 Secure 쿠키다. 비밀번호 변경 시 기존 세션도 무효가 된다.
- 변경 요청은 `APP_ORIGIN`과 Origin을 비교한다. 로그인 제한은 IP 해시별 15분당 10회 및 전체 100회다. 공감 쓰기는 식별자별 분당 100회다.
- DB 연결·업로드·검증 실패를 성공으로 응답하지 않는다. 서버 로그에는 비밀번호·계좌 변경값·사진·이야기를 출력하지 않는다.

## 로컬 실행

Node 24~26과 PostgreSQL이 필요하다. 저장소 루트에서 실행한다.

```bash
npm ci
cp .env.example .env
# .env에 DATABASE_URL, ADMIN_PASSWORD(9자 이상), SESSION_SECRET(32자 이상)를 설정한다.
node --env-file=.env --import tsx apps/web/scripts/migrate.ts
node --env-file=.env node_modules/next/dist/bin/next dev apps/web
```

`.env`는 Git에 포함하지 않는다. 로컬 기본 `APP_ORIGIN`은 `http://localhost:3000`이며 실제 접속 주소와 일치시킨다.

## 검증

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

API 통합·브라우저 테스트는 **전용 `benchmark_mat_test` 데이터베이스**와 실행 중인 웹 서버가 필요하다. 실제 운영 DB에서 실행하지 않는다. `.env.test`에 `DATABASE_URL`, `ADMIN_PASSWORD`, `SESSION_SECRET`, `APP_ORIGIN=http://127.0.0.1:4314`, `TEST_BASE_URL=http://127.0.0.1:4314`를 설정한다.

```bash
node --env-file=.env.test --import tsx apps/web/scripts/migrate.ts
node --env-file=.env.test node_modules/next/dist/bin/next start apps/web --hostname 127.0.0.1 --port 4314
# 별도 터미널에서 실행한다.
node --env-file=.env.test --import tsx --test apps/web/tests/api.integration.ts
cd apps/web
node --env-file=../../.env.test ../../node_modules/@playwright/test/cli.js test
```

브라우저 테스트는 macOS의 설치된 Chrome을 headless로 사용한다. 다른 환경은 `CHROME_EXECUTABLE`에 실행 파일 경로를 지정한다. 테스트에서 만든 레코드만 정리한다. `docs/screenshots/`의 이미지는 **검증용 데이터로 촬영한 화면**이며 실제 기부·현장 사용 증거가 아니다.

## Railway 배포

별도 외부 저장 서비스 없이 웹 서비스와 PostgreSQL 서비스 두 개를 사용한다. DB에는 영속 볼륨이 필요하다. 저장소 루트의 Dockerfile과 `.railway/railway.ts`를 사용하며 healthcheck는 `/api/health`다. [Railway 공식 healthcheck 문서](https://docs.railway.com/deployments/healthchecks)에 따라 앱은 제공된 PORT를 사용한다.

Railway CLI 5.54.1에서 기존 `railway.toml`의 배포 전 명령이 적용되지 않아 현재 IaC 형식으로 전환했다. `railway config plan`으로 변경 범위를 검토한 뒤 `railway config apply`를 실행하고 소스를 배포한다. `preserve()`는 Railway에 저장된 비밀 환경변수를 유지하며 소스에 값을 기록하지 않는다. 마이그레이션은 `preDeploy`에서 수행한다.

필수 환경변수:

| 변수 | 용도 |
| --- | --- |
| `DATABASE_URL` | 해당 프로젝트 PostgreSQL 연결 문자열 |
| `ADMIN_PASSWORD` | 운영팀 공유 비밀번호, 9자 이상 |
| `SESSION_SECRET` | 세션·공감 식별자 HMAC 키, 무작위 32자 이상 |
| `APP_ORIGIN` | 공개 HTTPS origin, 마지막 `/` 제외 |
| `DONATION_BANK` | 기본값 신한은행 |
| `DONATION_ACCOUNT_HOLDER` | 기본값 이돈혁 |
| `DONATION_ACCOUNT` | 기본값 111-111-111111 |
| `DONATION_ACCOUNT_CONFIRMED` | 실제 계좌 확인 전 `false` 유지 |

임시 계좌에는 입금하지 않도록 안내한다. 실제 계좌가 확정되면 환경변수를 바꾸고 재배포한다. SESSION_SECRET 변경 시 기존 공감 식별자와 연결이 끊기므로 비밀번호 변경과 별개로 관리한다. 도메인 변경 시 APP_ORIGIN도 함께 변경한다.

## 디자인 근거

- Figma `nEDJaJBFrdzBCa1WcgADHH`의 `170:349`: 흰 배경, ‘쉼, 펴’ 타이틀 및 아카데미 서명. 완성된 웹 레이아웃은 제공되지 않았다.
- `172:567`, `172:568`: 이서윤체 50px, 좌우 30px·상하 15px 패딩, 반경 50px, `rgba(245,230,165,0.6)` 크기 라벨. PNG 원본을 저장해 사용한다.
- 타이틀 SVG 원본은 `public/brand/title.svg`로 보관한다. 임시 Figma URL에 의존하지 않는다.
- 이야기 상세·목록·관리자 UI는 합의된 기능에 맞춰 새로 구성했다. 모바일 한 열, 중간 너비 두 열, 데스크톱 세 열 목록을 사용하며 루트 화면을 고정 크기로 제한하지 않는다.
- 이서윤체는 [흥국생명 공식 배포처](https://www.heungkuklife.co.kr/jsps/front/company/ci/digit-hand-font-info.jsp)의 원본 OTF를 수정 없이 사용한다. 본문 입력·관리자 도구는 시스템 글꼴을 사용한다.
