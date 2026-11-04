# 학교 소속 증빙 AI 검토 — #139

학교 소속 증빙에 표시된 발급처, 소속 근거, 유효 기간과 시각적 조작 징후를 로그인 사용자가 살펴보도록 돕는다. 학교 시스템을 조회하지 않으며, 소속·신원·발급 사실을 확인하거나 기부 납입과 글 작성 권한을 변경하지 않는다.

## 호출 계약

- `POST /functions/v1/analyze-school-evidence`
- `Authorization: Bearer <사용자 세션 JWT>`, `apikey: <Supabase 공개 키>`
- `Content-Type: image/jpeg | image/png | application/pdf`; 본문은 비식별화한 문서 바이트 한 개, 최대 10 MiB
- 학교·소속 표기가 남도록 가리고, 이름·학번·연락처·검증 코드 등 불필요한 개인 식별 정보는 영구적으로 제거한다. PDF의 가림 표시 아래 텍스트가 남지 않아야 한다. 서버가 비식별화 여부를 확인해 주지는 않는다.
- 응답에는 `review_type: school_affiliation`, `prompt_version`, `analyzed_at`, `model`, `assessment`와 고정된 `human_review_required: true`, `authenticity_verified: false`, `affiliation_verified: false`가 포함된다.
- `assessment`의 스키마와 공급자 오류 처리는 [기부 증빙 분석](evidence-ai-analysis.md)을 따른다. `inconclusive`는 소속 근거 누락·모호함·판독 불가 등을 뜻한다. `no_obvious_signs`도 소속 확인으로 해석하지 않는다.

## iOS 테스트

로그인한 뒤 **계정 → 학교 인증**을 연다. 외부 전송 안내를 확인하고 가상 에브리타임 화면이나 식별 정보를 제거한 학생증 사본을 한 장씩 선택한다. 결과는 화면에서 판정, 판독 한계, 추가 확인 항목으로 표시한다. 앱에서 실제 호출을 테스트하려면 연결된 Supabase 프로젝트에 함수가 배포되고 활성화되어 있어야 한다.

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
