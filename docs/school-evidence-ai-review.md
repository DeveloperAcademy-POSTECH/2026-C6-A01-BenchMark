# 학교 소속 증빙 AI 검토 — #139

학교 소속 증빙에 표시된 발급처, 소속 근거, 유효 기간과 시각적 조작 징후를 로그인 사용자가 살펴보도록 돕는다. 학교 시스템을 조회하지 않으며, 소속·신원·발급 사실을 확인하거나 기부 납입과 글 작성 권한을 변경하지 않는다.

## 호출 계약

- `POST /functions/v1/analyze-school-evidence`
- `Authorization: Bearer <사용자 세션 JWT>`, `apikey: <Supabase 공개 키>`
- `Content-Type: image/jpeg | image/png | application/pdf`; 본문은 비식별화한 문서 바이트 한 개, 최대 10 MiB
- 학교·소속 표기가 남도록 가리고, 이름·학번·연락처·검증 코드 등 불필요한 개인 식별 정보는 영구적으로 제거한다. PDF의 가림 표시 아래 텍스트가 남지 않아야 한다. 서버가 비식별화 여부를 확인해 주지는 않는다.
- 응답에는 `review_type: school_affiliation`, `prompt_version`, `analyzed_at`, `model`, `assessment`와 고정된 `human_review_required: true`, `authenticity_verified: false`, `affiliation_verified: false`가 포함된다.
- `summary`는 소속 표기 확인, 근거 부족, 재촬영 필요, 편집 징후 확인을 구분한다. 결과와 다음 조치는 서버가 지정한 한국어 문구를 쓴다. 기존 앱을 위해 `assessment` 계약도 유지한다.
- 학교명과 학생증 표기가 보이는 은행 연계 학생증을 검토한다. POSTECH과 우리은행 표기가 함께 읽히면 [학교 공식 발급 안내](https://freshman.postech.ac.kr/freshman/ot/ot_document.do)를 함께 표시한다. 앱 프로필 캡처도 소속 표기와 편집 징후를 검토한다. 로그인 계정과 명의자가 일치하는지는 발급처의 별도 확인이 필요하다.

## iOS 테스트

로그인한 뒤 **지도 집 → MY → 설정 → 학교 인증하기**를 연다. 학교 정보·재학생/졸업생·자료 종류를 고른 뒤 증빙을 첨부한다. OpenAI 전송 동의와 인증 요청하기를 명시적으로 확인해야 전송한다. 같은 화면에서 카메라로 직접 촬영하거나 파일 앱에서 JPEG·PNG·PDF를 고를 수도 있다. 학생증 앞면, 재학증명서, 소속이 표시된 앱 프로필을 검토한다. 앱의 결과 화면에는 **인증 완료** 또는 **반려**만 판정 내용으로 표시한다. 기존 판독 결과 중 `school_evidence_visible`은 인증 완료, `school_document_needed`·`retake_needed`·`manual_review_needed`는 반려로 표시한다. 통신이나 응답 확인이 실패하면 첨부를 유지하고 다시 요청할 수 있다.

판정과 판정 시각은 기기의 계정별 보호 저장소에 기록하고, 학교 인증에 재진입하면 결과를 첫 화면에서 복원한다. 이전 버전의 요약 기록도 읽을 수 있다. 저장에 실패하면 분석 결과를 메모리에 두고 저장만 재시도한다. 증빙 원본은 판정과 함께 저장하지 않는다. 입학연도·학과는 별도의 비공개 학적정보 RPC로 저장하며 쓰기 응답을 확인하면 다음 단계로 이동한다.

앱에서 실제 호출을 테스트하려면 연결된 Supabase 프로젝트에 함수가 배포되고 활성화되어 있어야 한다.

## 설정 및 운영 경계

기본 비활성화 상태다. 배포 및 운영 정책 합의 후 서버 환경의 `OI_SCHOOL_EVIDENCE_AI_ENABLED=true`로 켤 수 있다. `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OPENAI_API_KEY`, 선택적 `OPENAI_EVIDENCE_MODEL`은 기부 분석과 같은 방식으로 사용한다. 플랫폼 JWT 검증을 유지하며 함수는 분석 전후에 같은 로그인 사용자 세션을 확인한다. 익명 세션은 거부한다.

문서를 OpenAI Responses API에 `store: false`로 전송한다. 이 설정만으로 공급자의 모든 보관을 막을 수는 없다. 함수는 문서와 결과를 DB·Storage·애플리케이션 로그에 저장하지 않는다. 전체 요청 제한은 60초이며 한 isolate에서 동시 3건, 계정별 분당 5건을 허용한다. 로컬 테스트는 합성 파일과 대체 HTTP 응답을 사용한다.

```sh
npm --prefix supabase test
npm --prefix supabase run check
```

Needs confirmation:
- 인정할 학교·소속·문서 유형과 운영자 승인 기준, 학생 제출 및 승인 결과 표시 방식.
- 실자료의 외부 전송 고지·동의, 비식별화·보관·삭제 기준과 전역 사용량 한도.
- 실제 Supabase 배포, 실제 모델의 판독 품질 및 일반 계정 종단 검증.
