# BenchMark 메인 웹 디자인 초안

이슈 #38의 디자인 비교용 구현입니다. 전체 운영 전환 이슈 #37을 완료하거나, 개발·운영 브랜치를 병합하지 않습니다.

## 세 가지 방향

| 경로 | 참고 | 적용 방향 |
| --- | --- | --- |
| `/concepts/editorial` | https://www.mellon.org/ | 연한 올리브색 세로 내비게이션, 큰 공간 이미지, 명조 계열 제목과 편집형 프로젝트 구성 |
| `/concepts/immersive` | 사용자 제공 테니스 웹 이미지 | 푸른 배경, 대형 압축 타이포그래피, 투명 배경 벤치 레이어, 비대칭 구성 |
| `/concepts/tomorrow` | https://www.deartomorrow.org/about-us/ | 짙은 보라색과 크림색, 사진 위에 걸친 제목, 편지형 브랜드 메시지, 질문 펼치기 |

세 페이지의 상단·하단에서 다른 안으로 이동할 수 있습니다. 실제 파일럿 연결 대상은 `https://mat-web-production.up.railway.app`이며, 내부 소개·프로젝트·이야기는 문서 안의 섹션으로 이동합니다. 실적·후원 기관·확정 장소·기부 완료를 만들어 표시하지 않습니다.

## 공개 미리보기

- 1안: https://main-concepts-design-preview.up.railway.app/concepts/editorial
- 2안: https://main-concepts-design-preview.up.railway.app/concepts/immersive
- 3안: https://main-concepts-design-preview.up.railway.app/concepts/tomorrow

세 주소는 동일 작업 브랜치의 한 서비스에서 제공하며 로그인 없이 접속합니다. 개발 브랜치로 병합하지 않습니다.

## 구현 및 격리

- 기존 Next.js 앱을 사용하며 새 의존성을 추가하지 않습니다.
- `SiteShell`은 `/concepts` 하위 경로에서만 파일럿 헤더·푸터를 표시하지 않습니다. 기존 파일럿 마크업을 그대로 유지합니다.
- `BENCHMARK_DESIGN_PREVIEW=1`일 때만 `/`가 1안으로 이동합니다. 기존 배포에는 이 변수를 설정하지 않습니다.
- 미리보기는 기존 Railway 프로젝트의 별도 `design-preview` 환경과 `main-concepts` 서비스에 배포합니다. 운영 DB·변수·볼륨을 복제하지 않습니다.
- 새 서비스의 healthcheck는 `/concepts/editorial`이고 pre-deploy migration은 없습니다.
- 사진은 생성한 콘셉트 자산이며 실제 설치나 행사 사진이 아닙니다. 각 초안 하단에 이를 표시합니다.
- 색·서체·레이아웃 방향을 참고하며 원본 사이트 사진·로고·문구를 복제하지 않습니다. 서체 라이선스는 `apps/web/public/concepts/BebasNeue-OFL.txt`에 포함합니다.
- 초안은 공개 접속 가능하되 검색엔진에는 `noindex, nofollow`를 전달합니다.

## 검증

```bash
npm ci
npm run lint
npm run typecheck
npm test
npm run build
BENCHMARK_DESIGN_PREVIEW=1 node node_modules/next/dist/bin/next start apps/web --hostname 127.0.0.1 --port 4328
# 별도 터미널, apps/web 디렉터리:
TEST_BASE_URL=http://127.0.0.1:4328 npx --no-install playwright test tests/browser/concepts.spec.ts
```

브라우저 검사는 320/390/1440px 너비에서 가로 넘침, 이미지 로딩, 본문 바로가기, 페이지 전환, 내부 앵커, 파일럿 연결 대상, 질문 키보드 조작 및 기존 파일럿 셸을 확인합니다. 검증 후 실행한 서버와 headless 브라우저는 종료합니다.

## 검토 후 다음 단계

최종 디자인과 실제 콘텐츠가 선택되면 별도 요청으로 운영 전환 범위를 결정합니다. 이번 초안은 운영 데이터 이전, 새 결제 기능, 실제 설치 약속을 포함하지 않습니다.
