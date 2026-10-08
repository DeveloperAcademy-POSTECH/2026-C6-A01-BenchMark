# BenchMark 메인 웹 확정 디자인 및 이전 초안

이슈 #38의 디자인 비교 및 2026-09-27 팀 디자이너 확정안 구현입니다. 전체 운영 전환 이슈 #37을 완료하거나, 개발·운영 브랜치를 병합하지 않습니다.

## 확정안

- Figma: https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=428-738
- 공개 URL: https://main-concepts-design-preview.up.railway.app/benchmark
- 1784×3985 프레임의 색상, 원본 이미지·SVG, Griun OMIRI·Hedvig Letters Serif·Pretendard 서체를 반영합니다.
- 1100px 이하에서는 콘텐츠를 재배치하고 600px 이하에서는 단일 열로 표시합니다. 모바일 프레임이 없어 데스크톱의 읽기 순서와 계층을 기준으로 구성했습니다.
- FAQ는 디자인처럼 펼쳐진 상태로 시작하며 키보드로 접고 펼칠 수 있습니다. 중복된 세 번째 질문은 답변에 맞춰 “다음 프로젝트는 무엇인가요?”로, “예정빈다”는 “예정입니다”로 교정했습니다.
- 기존 세 초안은 비교 기록으로 유지합니다. 확정안에는 초안 선택 UI를 표시하지 않습니다.

## 이전 세 가지 방향

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
- `SiteShell`은 `/benchmark`와 `/concepts` 하위 경로에서 파일럿 헤더·푸터를 표시하지 않습니다. 기존 파일럿 마크업을 그대로 유지합니다.
- `BENCHMARK_DESIGN_PREVIEW=1`일 때만 `/`가 확정안 `/benchmark`로 이동합니다. 기존 배포에는 이 변수를 설정하지 않습니다.
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
TEST_BASE_URL=http://127.0.0.1:4328 npx --no-install playwright test tests/browser/brand-home.spec.ts tests/browser/concepts.spec.ts
```

브라우저 검사는 320/390/1440px 너비에서 가로 넘침, 이미지 로딩, 본문 바로가기, 페이지 전환, 내부 앵커, 파일럿 연결 대상, 질문 키보드 조작 및 기존 파일럿 셸을 확인합니다. 검증 후 실행한 서버와 headless 브라우저는 종료합니다.

## 검토 후 다음 단계

팀 디자이너 확정 디자인을 반영했으며, 운영 전환 범위는 별도 요청으로 결정합니다. 이번 초안은 운영 데이터 이전, 새 결제 기능, 실제 설치 약속을 포함하지 않습니다.
