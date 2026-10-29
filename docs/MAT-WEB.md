# 쉼, 펴 — 돗자리 파일럿 웹

## 실행 환경과 소스

2026-10-26 사용자 요청으로 기존 Sites 이전 검증 작업(#76)을 운영 전환 작업으로 이어간다. 파일럿은 `apps/web`, 오이기부는 `apps/oi-web`, 팀 소개는 `apps/team-web`에서 관리한다. 각 `.openai/hosting.json`은 기존 Sites ID를 유지한다.

Vinext/React/TypeScript 서버를 Sites Worker에서 실행하고, 구조화된 데이터는 D1, 비공개 사진은 R2에 저장한다. PostgreSQL 연결 문자열과 Railway 서비스·볼륨은 새 런타임에 필요하지 않다. `database/migrations`는 이전 PostgreSQL 원본 확인용 과거 기록이다. Sites에 실행하지 않는다. 현재 스키마·적용 이력은 `apps/web/drizzle`에 있다.

## 보존하는 기능

- 기존 이야기 UUID와 `/stories/:id`, 제목·본문·익명 이름·공개 및 입금 확인 조건
- 네 종류 반응·선택 취소·브라우저별 서명 식별자
- 예약·사진·재전송 중복 방지·예약에서 이야기 등록
- 관리자 비밀번호·8시간 세션·revision 충돌 방지·공개 상태 관리
- 활동 로그·관리자 브라우저 제외·필터·CSV
- 예약 삭제 시 예약 자료·사진 제거 및 등록된 이야기 유지

실제 배포된 파일럿 소스를 기준으로 복원했다. 이전 문서의 전화번호 필수·500바이트·자유 금액 1원·같은 번호 한 이야기 제한을 다시 도입하지 않는다. 현재 코드는 이메일, 본문 1,000바이트, 최소 10,000원을 검증하고 같은 돗자리 번호의 여러 이야기를 허용한다. 이 파일럿 정책을 오이기부의 미정 명패 기준으로 취급하지 않는다.

## 외부 기능

사진은 R2에 저장하지만 변환은 기존 서명된 Netlify 함수를 유지한다. 5MB 이하 JPG/PNG/WebP 정지 사진의 디코딩·방향 보정·긴 변 1600px 이하 JPEG 변환을 담당한다. 단기 D1 작업·일회성 원본 읽기·HMAC 서명을 사용한다. `SESSION_WRAP_KEY`와 `PHOTO_PROCESSOR_URL`이 필요하다. 사진 변환까지 Sites 내부로 통합한 상태는 아니다. 오이기부 Google 로그인은 기존 Supabase Auth를 유지한다. 두 경로에 Railway는 참여하지 않는다.

## 로컬 검증

Node 24~26에서 앱별 잠금 파일로 설치한다. 루트에는 런타임 의존성이 없다.

```bash
npm run sites:check
npm --prefix apps/web ci
npm --prefix apps/web run typecheck
npm --prefix apps/web test
npm --prefix apps/web run build
npm --prefix apps/oi-web ci
npm --prefix apps/oi-web run typecheck
npm --prefix apps/oi-web run build
npm --prefix apps/team-web ci
npm --prefix apps/team-web run typecheck
npm --prefix apps/team-web run build
```

각 앱에서 `npm run dev` 또는 빌드 후 `npm start`로 미리보기를 실행한다. 출력되는 주소에 `APP_ORIGIN`을 맞춘다. 루트 `.env.example`은 파일럿의 키 이름을 안내한다. 실제 환경 값은 Git에 넣지 않는다. 빌드된 로컬 Worker의 HTTP 검증용 환경변수와 D1 준비 절차는 `.github/workflows/sites-web.yml`을 따른다. 로컬 D1과 운영 D1은 분리된다. 앱 README의 로컬 D1 절차대로 생성된 SQL을 적용한다.

## 배포와 전환

Sites 스킬의 공식 source helper로 해당 Site 소스를 열고, 이 저장소의 앱 소스를 반영한 뒤 검사·빌드·패키징·배포한다. GitHub push만으로 Sites가 배포되지는 않는다. 기존 ID·audience·D1/R2 바인딩을 유지하고 공식 deployment ID·성공 상태·URL을 확인한다. 환경변수는 Sites 도구로 관리한다.

`MIGRATION_ENABLED`는 평상시 `false`다. 이전 창에서만 별도 `MIGRATION_TOKEN`을 설정하고 요청의 `x-migration-token` 헤더로 전달한다. Site 방문 권한만으로 원본 내보내기·가져오기를 허용하지 않는다. 전환 후 비활성화와 실제 404를 확인한다.

완료 기준과 증거는 [Sites 전환 기록](SITES-CUTOVER.md)에 관리한다. 최신 원본 대조 → 전환 중 쓰기 보존·증분 반영 → 공개 링크·OAuth 콜백 전환 → 실제 예약·사진·관리자 검증 → 이전 API 폐쇄 → Railway 실행·잔여 과금 확인 순서다. 검증 배포만으로 완료 처리하지 않는다.

## 활동 로그 일자 조회 — PR #36 통합

한국 시간 일자별·기간별 조회와 UTC/KST CSV 열을 제공합니다. `date`와 `from`/`to`는 동시에 사용할 수 없습니다. 기존 Sites D1 조회·보관·관리자 인증 구조를 유지합니다. main의 과거 PostgreSQL·카메라 제거 변경을 현재 Sites 코드에 재적용하지 않습니다.
