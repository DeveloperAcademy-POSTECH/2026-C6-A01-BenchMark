# 오이기부 웹 — 로그인·기부 안내

2026-10-12, 이슈 #64. Android hi-fi #63과 같은 녹색 팔레트(708C40, 435426, B0C85B)와 로고·벤치 이미지로 웹의 분위기를 연결한다. 앱 화면을 복제하지 않고 데스크톱에서는 소개·이미지와 안내·행동을 나란히 배치하며 작은 화면에서는 세로로 읽는다. 이미지는 기존 앱 디자인 자산이며 승인된 실제 캠퍼스 벤치나 부착 실적의 증거가 아니다.

## 경로와 기존 기능

- `/`: 오이기부 소개, 기부 시작, 파일럿 이야기 연결
- `/donate`: 공식 기부 안내; 로그인 없이 열람 가능
- `/login`: Android #44와 같은 Supabase 프로젝트의 Google PKCE 로그인
- `/auth/callback`: 일회성 코드 교환; 성공하면 `/` 또는 `/donate`로 복귀
- `/pilot`: 이전 첫 화면의 돗자리 이야기 읽기
- `/stories`, `/stories/:id`, `/reserve`, `/admin`, `/camera` 및 API·저장 데이터는 보존

루트 `/`와 `/about`의 도착 화면은 새 홈으로 변경된다. 기존 이야기 고유 URL은 유지된다. 예약 폼은 기존 돗자리 파일럿용이며 벤치 참여 신청이나 학교 기부 확인으로 사용하지 않는다.

## 서버 환경 설정

`.env.example`의 설정을 `apps/web/.env.local` 또는 배포 서비스 환경에 지정한다. 실제 키를 커밋하지 않는다.

```dotenv
APP_ORIGIN=http://127.0.0.1:3000
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
POSTECH_DONATION_URL=
```

- `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`: Android와 같은 프로젝트. publishable 또는 기존 anon 공개 키만 사용한다. service_role/secret key를 사용하지 않는다.
- `APP_ORIGIN`: 배포 HTTPS origin, 경로·끝 슬래시 제외. 로컬 HTTP는 localhost/127.0.0.1만 허용한다.
- Supabase Auth URL Configuration의 Redirect URLs에 정확한 `${APP_ORIGIN}/auth/callback`을 등록한다. Google OAuth 공급자가 활성화되어 있어야 한다. Android 콜백 목록을 보존한다.
- `POSTECH_DONATION_URL`: 학교와 합의한 HTTPS `postech.ac.kr` 또는 하위 도메인 URL. 비어 있거나 잘못된 값이면 준비 중 안내를 표시한다. 운영 연결 주소는 아직 미정이다.

로그인은 서버 전용 쿠키 클라이언트를 사용한다. PKCE verifier·세션 쿠키는 HttpOnly·SameSite=Lax이며 운영 HTTPS에서는 Secure다. Proxy가 토큰을 갱신하고 `getUser`로 검증한다. 인증 응답은 private/no-store이며 사용자 세션을 관리자 권한으로 사용하지 않는다. 로그아웃은 웹 세션만 종료해 Android 세션을 유지한다. 로그인 서버 액션은 Next.js의 Origin 검증 및 정확한 APP_ORIGIN 검사를 적용한다.

학교 사이트 이동은 납입 완료로 처리하지 않는다. 결제·약정·영수증·취소·환불은 학교가 처리한다. 웹 계정과 납입·명패 상태의 서버 연동은 이번 범위에 포함되지 않는다.

## 검증 결과 — 2026-10-12

- lint·타입 검사·production build 성공, 단위 테스트 12개 및 격리 PostgreSQL API 통합 테스트 2개 통과
- 기존 카메라 2개·스토리/관리자/예약 1개·새 웹 반응형/탐색 1개, 브라우저 테스트 4개 통과
- 실제 Android 설정으로 Google 로그인 서버 액션의 authorize URL·PKCE challenge·HttpOnly/Secure/SameSite 쿠키 검사 1개 통과. OAuth 이동은 브라우저에서 가로채 실제 계정 인증을 수행하지 않았다.
- 실제 Supabase `/auth/v1/settings`: HTTP 200, Google enabled true
- npm audit: 기존 Next.js·sharp·eslint 관련 9건(critical 1/high 8). 신규 Supabase 패키지 관련 항목은 없다. 이 PR에서는 무관한 라이브러리 업그레이드를 하지 않았다.

## 검증 명령

```bash
npm run lint
npm run typecheck
npm test
npm run build
npm run test:integration
cd apps/web
npx --no-install playwright test
# Auth-configured server, without logging in to a real account:
TEST_AUTH_CONFIGURED=true npx --no-install playwright test google-login.spec.ts
```

통합·기존 스토리 브라우저 테스트는 이름이 `benchmark_mat_test`인 격리 DB를 요구한다. 환경 변수와 서버 시작 절차는 `.github/workflows/mat-web.yml`을 참고한다. `oi-web.spec.ts`는 공식 기부 URL 미설정·로그인 미설정 상태를 검증하므로 해당 두 설정을 비운 서버에서 실행한다.

Needs confirmation:
- 실제 Google 계정 로그인·콜백·새로고침 세션 복원·로그아웃 인수 검증
- 운영 웹 origin과 Supabase의 웹 콜백 허용 목록
- 학교가 승인한 기부 URL 및 벤치 참여 신청·학교 확인 계약

![데스크톱 홈](web-oi/home-1440.png)
![모바일 홈](web-oi/home-390.png)

## 개편 웹 미리보기

Railway `benchmark-mat-pilot` / `design-preview` / `oi-web-preview`를 사용한다. `OI_WEB_PREVIEW=1`이면 검색 제외 헤더를 제공하고 `/stories`, `/pilot`, `/reserve`, `/admin`은 기존 파일럿 운영 주소로 이동한다. 운영 DB·관리자 변수·마이그레이션은 복제하지 않는다. 기존 `main-concepts` 서비스와 운영 서비스는 별도로 유지한다.

서비스 이름은 **오이기부**, 제작팀 이름은 **BenchMark**다. 공개 제목·로고·주요 안내는 서비스명을 사용하며 팀 이름은 제작팀 표기에만 사용한다.
