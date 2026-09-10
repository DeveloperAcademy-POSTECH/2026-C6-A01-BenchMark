# 서비스 소개 및 사전신청 웹

## 확정 범위 (2026-09-10)

서비스 소개와 이름·휴대폰 번호를 저장하는 사전신청만 구현한다. Figma 기준은 사용하지 않는다. 실제 결제, 지도, 기부 이력, 관리자 화면, 알림 발송은 범위 밖이다. 기존 PRD 초안보다 이번 사용자 결정이 이 웹의 범위에 우선한다.

## 구성

- Next.js App Router + React + TypeScript: 소개 화면과 서버 API를 같은 앱으로 배포한다.
- PostgreSQL + pg: 데이터는 웹 컨테이너 외부 DB에 보관한다. 앱 재배포로 신청 정보가 사라지지 않는다.
- Zod: 입력 검증은 클라이언트와 서버에서 같은 규칙을 사용한다.
- npm workspaces: `apps/web`에 웹을 분리해 이후 iOS 코드와 독립적으로 빌드한다.
- Docker + Railway: 웹 1개와 PostgreSQL 1개가 기본 구성이다. Docker는 Node 24 LTS를 사용한다.

## 로컬 실행

Node 24 LTS와 PostgreSQL 18을 권장한다. 비어 있는 개발용 DB를 준비한다.

```bash
npm ci
cp .env.example apps/web/.env.local
# apps/web/.env.local의 DATABASE_URL 및 APP_ORIGIN을 개발 환경에 맞춘다.
cd apps/web
node --env-file=.env.local --import tsx scripts/migrate.ts
cd ../..
npm run dev
```

`.env.local`은 Next.js에서 자동으로 읽지만 단독 DB 스크립트는 자동으로 읽지 않는다. 위처럼 `--env-file`을 사용하거나 환경 변수를 명시적으로 주입한다. `localhost`와 `127.0.0.1`은 서로 다른 origin이므로 브라우저 주소와 `APP_ORIGIN`을 정확히 일치시킨다. 경로나 마지막 `/`는 넣지 않는다.

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

DB 통합 테스트는 `registrations`와 `registration_rate_limits`를 비우므로 **반드시 별도 일회용 DB**에서만 실행한다.

```bash
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/benchmark_test npm run db:migrate
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/benchmark_test ALLOW_TEST_DATABASE_RESET=yes npm run test:integration -w apps/web
```

브라우저 테스트는 실행 중인 테스트용 앱(기본 `http://127.0.0.1:3100`)을 사용한다. `APP_ORIGIN`도 같은 값이어야 한다. Playwright Chromium이 필요하며, 로컬 설치된 Chrome은 `CHROME_EXECUTABLE`로 지정할 수 있다.

```bash
npm run start -w apps/web -- --port 3100
# 별도 터미널에서:
cd apps/web
npx playwright test
```

## 테스트 모드와 실제 접수

기본 `REGISTRATION_MODE=test`에서는 화면에 테스트임을 표시하고, 번호는 `010-0000-숫자 4자리`만 받는다. 이름에도 실제 개인정보 대신 테스트 값을 사용한다. 입력은 실제 PostgreSQL에 저장되며 mock 성공으로 대체하지 않는다. 기부나 연락은 발생하지 않는다. 테스트 레코드의 만료 시각은 7일 후로 기록한다.

실제 접수는 `REGISTRATION_MODE=live`, `PRIVACY_RETENTION_DAYS`, `PRIVACY_CONTACT_EMAIL`이 있어야 시작된다. 보유 기간은 1~365일 범위의 정수다. 실제 운영 주체·목적·보유 기간·문의처와 화면 문구는 회의에서 확정한 뒤 적용해야 한다. live 전환 전 테스트 데이터는 별도 DB로 분리한다.

수집 동의는 기본 미선택이다. 신청자 목록 조회 API를 공개하지 않으며, 개인정보·DB 오류·연결 문자열을 로그에 남기지 않는다. 연락처 인증은 이번 범위에 없으므로 번호 소유권을 검증한 데이터로 취급하면 안 된다.

## 추가 신청 항목을 붙이는 방법

1. `src/lib/registration.ts`의 `registrationFields`에 표시 정보와 키를 추가하고 `registrationSchema`에 검증을 추가한다.
2. `formVersion`을 증가시킨다. 구버전으로 열어둔 브라우저의 제출은 새로고침 안내와 함께 거부된다.
3. `save-registration.ts`에서 새 검증 값만 `answers` JSONB에 명시적으로 매핑한다. 임의의 클라이언트 필드를 통째로 저장하지 않는다.
4. 선택형/날짜 등 새로운 입력 종류가 필요하면 폼 렌더러와 필드 오류 타입을 확장한다. 동의 안내의 수집 항목도 같이 수정한다.
5. 이전 신청에는 기존 `form_version`과 빈 `answers`를 유지한다. 새 필드가 없는 것을 자동 동의 또는 응답으로 해석하지 않는다.
6. 검색·정렬·유일성 보장이 필요한 필드만 새 SQL migration으로 열/인덱스를 추가한다.

## API 동작

`POST /api/registrations`는 JSON으로 `name`, `phone`, `consent: true`, `formVersion: 1`을 받는다. 이름은 1~50자, 번호는 010으로 시작하는 11자리다. 공백·하이픈·국제 표기는 서버에서 정규화한다. 동의 누락, 미등록 키와 구버전 폼은 거부한다.

- 200: DB 트랜잭션 완료. 동일 번호의 재요청도 같은 결과를 반환하며 기존 이름을 덮어쓰지 않는다.
- 403 / 415 / 413 / 422: origin / 미디어 타입 / 4KB 초과 / 검증 오류.
- 429: DB 공유 카운터 기준 전체 분당 60건 초과. 이 값은 초기 테스트 규모 기준이며 공개 접수 전 트래픽에 맞게 조정해야 한다.
- 503: DB·환경 설정 장애. 성공으로 표시하지 않으며 폼 입력을 유지한다.

DB의 UNIQUE 제약으로 재시도와 동시 요청의 중복을 방지한다. 브라우저 타임아웃은 저장 실패를 확정하지 않으므로 재시도 가능 안내를 표시한다. 신청 내용은 브라우저 저장소에 남기지 않는다.

## Railway 배포

저장소 루트를 빌드 루트로 사용한다. `Dockerfile`과 `railway.toml`을 함께 사용한다. 별도 Railway 프로젝트에 웹 서비스와 PostgreSQL을 추가한 후 연결한다.

1. 웹 서비스에 PostgreSQL의 `DATABASE_URL`을 변수 참조로 연결한다. 비밀번호를 저장소에 넣지 않는다.
2. `APP_ORIGIN`에 웹 서비스의 최종 HTTPS origin을 넣고 `REGISTRATION_MODE=test`를 설정한다.
3. 배포 전 명령 `npm run db:migrate`가 schema_migrations 기록 및 advisory lock으로 한 번씩 migration을 적용한다.
4. `/api/health`가 테이블 접근 및 환경 구성을 확인한다. 공개 응답에는 상세 오류나 개인정보를 포함하지 않는다.
5. 같은 이미지의 정리 전용 Railway Cron 서비스를 추가한다. 시작 명령은 `npm run db:purge -w apps/web`, 주기는 매시간이다. DB 변수만 연결하고 웹 포트는 열지 않는다. 만료 레코드는 매시간 삭제되며, 접수 시에도 정리된다.
6. **실제 접수 전 정리 작업의 성공 로그와 백업 보존 기간을 확인한다.** 트래픽이 없는 동안에도 삭제하려면 Cron이 필수다. 백업 내 개인정보 보존은 별도 운영 정책을 적용한다.

Hobby 구독 보유가 추가 웹/DB 사용량이 모두 무료라는 뜻은 아니다. 프로젝트·비용·공개 범위를 확인한 뒤 배포한다. 이 문서와 설정 파일만으로 Railway 배포 또는 원격 데이터 저장이 완료됐다고 판단하지 않는다.

현재 검색 엔진 노출은 `noindex`로 차단한다. 공개 출시 시 운영 정책·수집 안내·연락처를 확정하고 metadata를 수정한다. 공개 트래픽을 받기 전 악성 요청 방어와 운영 조회/정정 절차도 정해야 한다.
