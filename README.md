# 2026-C6-A01-BenchMark

- [오이기부 프로젝트 맥락과 기획](project.md)
- [AI 에이전트 공통 작업 지침](AGENTS.md)
- [팀 검토 중인 아키텍처·협업 제안](docs/architecture.md)
- [웹 실행 및 Sites 배포](docs/MAT-WEB.md)
- [Sites 운영 전환 상태와 남은 검증](docs/SITES-CUTOVER.md)

웹은 기존 Sites 배포 소스에 맞춰 `apps/web`(돗자리 파일럿), `apps/oi-web`(오이기부), `apps/team-web`(팀 소개)로 관리한다. 앱별 잠금 파일로 의존성을 설치하며 Railway 배포 설정은 사용하지 않는다. 실제 원본 데이터 대조·운영 전환·서비스 종료 여부는 위 전환 기록을 확인한다.

## iOS 실행 전 Supabase 설정

최신 코드를 받은 뒤 기존 `52gibu` 프로젝트에 접근 가능한 Supabase CLI 인증으로 한 번 실행합니다.

```sh
python3 scripts/configure-ios-service.py --from-cli --http-check
```

본 앱과 App Clip의 Git 제외 `Service.local.plist`를 생성하고 실제 공개 API 연결을 검사합니다. 이후 Xcode에서 `OiDonation`을 빌드합니다. 두 타깃은 빌드 시작 시 각 설정을 검증하며, 누락되거나 잘못된 설정이면 준비 명령을 안내하고 중단합니다. 빌드 중에는 키 조회나 서버 호출을 하지 않습니다.

CI에서는 기존 프로젝트의 공개 클라이언트 키를 `OI_SUPABASE_PUBLISHABLE_KEY` 환경변수로 주입하고 `python3 scripts/configure-ios-service.py`를 빌드 전에 실행합니다. 키 값·프로파일·개인 서명 설정은 커밋하지 않습니다. 자세한 내용은 [Supabase 연동 문서](docs/supabase-flow.md#로컬-실행-설정)를 참고합니다.

# 깃 전략

### 태그 컨벤션

`init` : 가장 처음 Initial Commit에 태그 붙이기

`feat` : 새로운 기능 구현 시 사용

`fix` : 버그나 오류 해결 시 사용

`docs` : README, 템플릿 등 프로젝트 내 문서 수정 시 사용

`setting` : 프로젝트 관련 설정 변경 시 사용

`add` : 사진 등 에셋이나 라이브러리 추가 시 사용

`refactor` : 기존 코드를 리팩토링하거나 수정할 시 사용

`chore` : 별로 중요한 수정이 아닐 시 사용

### 커밋 컨벤션

태그는 반드시 **소문자**로 작성합니다.

내용은 한글로 작성합니다.

제목이 **50자**를 넘지 않도록, 간단하게 명령조로 작성합니다. 설명이 필요한 경우 description에 작성합니다.

```markdown
[feat] 로그인 기능 구현
```

### 브랜치 컨벤션

태그/#이슈번호-작업하는 파일

```markdown
feat/#1-loginUI
```

### 브랜치 전략

`main` : 출시(release)에 사용하는 브랜치입니다.

`develop` : 개발된 기능들을 최종적으로 합쳐서 확인하는 브랜치입니다.

- 기본 브랜치이며 개발을 마친 후에 반드시 develop에 머지합니다.
- 개인 브랜치에서 작업을 마치면, 개인 브랜치에서 develop 브랜치를 머지한 후에 develop에 pull request를 요청합니다.

`feature` : 태그를 붙이는 모든 브랜치들을 말합니다. 기능 개발, 버그 수정 등을 반드시 이 브랜치에서 진행해주세요.
