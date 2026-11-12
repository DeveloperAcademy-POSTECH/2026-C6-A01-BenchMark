# 증빙 AI 시각 분석 — #116

> **2026-11-09 / #258:** 이 문서는 종료한 기부 증빙 기능의 구현 기록이다. 아래 운영 배포·실행 절차는 더 이상 사용하지 않는다. [현재 적용 순서](donation-evidence-retirement.md).

## 구현 범위

2026-11-02 사용자 요청에 따라 버튼·화면 없이 Supabase Edge Function `analyze-evidence`를 추가했다. 기존 `oi_capabilities()` 운영자 권한과 비공개 `oi-evidence` 저장소를 사용한다. 신규 테이블·마이그레이션·자동 승인·원격 배포는 포함하지 않는다.

AI는 시각적 조작 징후와 문서 내부 불일치를 검토하는 참고 도구다. 원본 진위 인증, 은행·학교 납입 확인, 다른 신청과의 중복 증빙 탐지, EXIF·PDF 전자서명 감정은 수행하지 않는다. 판정 확률이나 사기 확정 값을 제공하지 않는다.

| `assessment.verdict` | 의미 |
| --- | --- |
| `suspicious` | 위치와 관찰 근거가 있는 조작 의심 징후가 있음 |
| `no_obvious_signs` | 읽을 수 있는 자료에서 뚜렷한 징후를 찾지 못함. 원본 인증이 아님 |
| `inconclusive` | 판독 상태·자료 누락·불확실성 때문에 판단하기 어려움 |

결과에는 `readability`, `findings`(종류·위치·관찰 내용), `limitations`, `manual_checks`가 포함된다. `human_review_required: true`, `authenticity_verified: false`와 고정 안내문은 모델 응답과 별도로 서버가 붙인다. 분석 실패에는 결과를 만들지 않는다. 운영자 검토 API를 호출하거나 제출 상태를 변경하지 않는다. #234 이후 증빙 검토 결과는 작성 권한과 별개다.

## 서버 설정과 호출

| 환경 변수 | 용도 |
| --- | --- |
| `SUPABASE_URL` | Edge Function에 제공되는 기존 프로젝트 URL |
| `SUPABASE_ANON_KEY` | 기본 공개 키. 사용자 JWT와 함께 RLS 적용 |
| `OPENAI_API_KEY` | 서버 secret에만 저장할 OpenAI API 키 |
| `OPENAI_EVIDENCE_MODEL` | 선택 사항. 기본 `gpt-4.1-2025-04-14`; 이미지·PDF 입력과 Structured Outputs를 지원하는 모델 필요 |

service-role 키를 사용하지 않는다. 키는 iOS·웹 번들·공개 환경 변수·Git·로그에 넣지 않는다. 키가 없으면 `503 analysis_not_configured`로 종료한다. OpenAI 호출은 외부 패키지 없이 표준 `fetch`와 Web API를 사용한다.

원격 설정·배포는 수행하지 않았다. 추후 승인된 배포 시 기존 프로젝트를 확인하고 서버 secret을 설정한 뒤 단일 함수만 배포한다. 기본 플랫폼 JWT 검증을 유지하고 `--no-verify-jwt`를 사용하지 않는다. 내부에서도 Auth `/user`로 세션을 검증한다. 대상 명령은 `supabase functions deploy analyze-evidence --project-ref kfzfzarslqdqmrazohej`다.

```http
POST /functions/v1/analyze-evidence
Authorization: Bearer <operator-user-access-token>
apikey: <supabase-publishable-key>
Content-Type: application/json

{"evidence_id":"<submitted-evidence-uuid>"}
```

서버·네이티브 클라이언트에서 호출할 수 있다. 브라우저 버튼 위치·origin이 정해지지 않아 CORS 허용 목록과 화면 연결은 추가하지 않았다. 웹에 연결할 때는 해당 origin만 명시적으로 허용해야 한다.

## 처리와 보안 경계

1. 실제 세션과 `oi_capabilities().operator === true`를 확인한다. 제출자나 일반 사용자는 호출할 수 없다.
2. UUID 하나만 받고 기존 신청의 현재 `pending` 자료를 읽는다. 클라이언트가 제공한 URL·파일·Storage 경로·설명문은 받지 않는다.
3. 기존 사용자 JWT로 RLS를 적용한 상태에서 파일을 내려받는다. JPEG·PNG·PDF의 MIME과 시그니처, 스트리밍 실제 크기(최대 10MiB)를 확인한다. 시그니처 검사는 완전한 디코딩이나 파일 안전성 인증이 아니다.
4. 이미지는 `input_image`와 `detail: high`, PDF는 base64 `input_file`로 전달한다. 원본 파일명·계정 식별자를 모델에게 전달하지 않는다. 문서 속 명령을 신뢰하지 않고 링크·도구 실행을 허용하지 않는다.
5. strict JSON Schema와 실행 시 검증을 모두 적용한다. 응답 거부·중단·잘못된 JSON·불완전한 출력은 실패다. 판독 불가 자료의 `no_obvious_signs`나 근거 없는 `suspicious`도 거절한다.
6. 반환 직전에 운영자 권한과 신청 상태·파일 경로·제출 시각을 다시 확인한다. 검토·재제출이 발생했으면 결과 대신 오류를 반환한다.

결과에 `evidence_id`, `submitted_at`, 원본 바이트의 `sha256`, `analyzed_at`, `model`, `prompt_version`을 포함해 분석 대상을 구분한다. 이후 표시·저장할 때도 최신 신청과 대조해야 한다. SHA-256은 바이트 식별용이며 진위 증명이 아니다. 재확인 직후 상태가 바뀔 수 있으므로 결과 자체를 승인 근거의 최신성 보증으로 사용하지 않는다.

응답은 `Cache-Control: no-store`이며 원본 경로·공개/서명 URL을 반환하지 않는다. 분석 결과를 DB나 애플리케이션 로그에 저장하지 않는다. 개인정보를 옮겨 적지 않도록 모델에 지시하지만 완전한 비식별화를 보증하지 않으므로 결과 역시 운영자용 민감 자료로 취급한다. `store: false`는 공급자의 모든 보관을 제거한다는 보장이 아니다.

| 상태 | 예시 오류 |
| --- | --- |
| 400 / 415 | `invalid_request`, `json_required`, `unsupported_document` |
| 401 / 403 | `authentication_required`, `authentication_failed`, `operator_required` |
| 404 / 409 | `evidence_not_found`, `evidence_not_pending`, `evidence_changed` |
| 413 / 422 | `payload_too_large`, `analysis_refused`, `empty_document` |
| 429 | `analysis_busy`, `analysis_rate_limited`, `provider_rate_limited` |
| 502 / 503 / 504 | `invalid_analysis_response`, `incomplete_analysis`, `analysis_unavailable`, `analysis_not_configured`, `analysis_timeout` |

전체 요청은 60초 제한이며 클라이언트 취소를 전파한다. 같은 isolate 안에서 동일 증빙의 중복 실행을 차단하고 동시에 최대 3건, 운영자별 1분 5건으로 제한한다. 분산 전역 제한·영구 캐시·월 비용 한도는 아니다. 재시작·다른 isolate에서 재호출되면 다시 과금될 수 있다. 자동 재시도는 하지 않는다. 실제 운영 연결 전에 전역 비용·요청 제한을 정해야 한다.

## 검증

Node 24 이상에서 별도 의존성 설치 없이 자동 테스트를 실행한다. HTTP·Storage·OpenAI를 격리해 권한, 경로, 크기·형식, PDF/이미지 요청, 응답 검증, 실패·취소, 재제출·권한 회수, 중복 호출·빈도 제한을 확인한다. 실제 증빙의 판별 정확도 평가와 구분한다.

```sh
npm --prefix supabase test
```

Deno가 준비된 환경에서 진입점 타입 검사를 실행한다. CI는 이 검사와 Node 테스트를 실행하며 실제 키를 사용하지 않는다.

```sh
npm --prefix supabase run check
```

실제 API 연결 검사는 Git에서 제외된 로컬 환경 파일의 키를 사용하며 **가상 PDF 한 장만** 전송한다. 명령행에 키를 직접 쓰지 않는다. 과금될 수 있으며 원격 Supabase 배포·사용자 로그인·실제 증빙 판별 검증을 대신하지 않는다.

```sh
node --env-file=.env.evidence-ai.local supabase/tests/evidence-analysis.live.mjs
```

2026-11-02 실제 OpenAI 연결 검사는 성공했다. 기본 모델이 가상 PDF를 `inconclusive`로 반환했고 실행 시 스키마 검사도 통과했다. 실제 개인정보·증빙은 전송하지 않았으며, 이 결과로 정상/조작 판별 정확도를 검증했다고 주장하지 않는다.

Needs confirmation:
- 실자료를 외부 AI에 전송하기 전 고지·동의, 최소 수집·가림 범위, 공급자 보관 조건과 팀 보관·삭제 정책.
- 정상·편집·재촬영·저화질 자료로 오탐·미탐 평가와 운영자 판단 기준. 현재 테스트로 조작 탐지 정확도를 보증하지 않는다.
- 버튼 위치, 웹 CORS 허용 origin, 결과 보관 여부, 운영 배포와 전역 사용량 제한.

공식 근거: [OpenAI 이미지 입력](https://developers.openai.com/api/docs/guides/images-vision), [파일 입력](https://developers.openai.com/api/docs/guides/file-inputs), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [GPT-4.1](https://developers.openai.com/api/docs/models/gpt-4.1), [Supabase 인증](https://supabase.com/docs/guides/functions/auth).

## 2026-11-05 제출자 즉시 검사 (#161)

사용자 요청으로 `analyze-donation-evidence`를 추가한다. 기존 `analyze-evidence`의 운영자 전용 권한은 유지하고, 새 경로는 인증된 제출자 본인의 `pending` 자료만 허용한다. 두 경로는 동일한 `analyzeDocument`·프롬프트·판정 규격을 사용한다. 새 경로는 실제 납입/진위를 확인하거나 작성 권한을 부여하지 않는다. iOS가 비공개 접수 후 호출하며, 결과는 앱의 현재 화면에 표시한다. 원격 배포와 검증 상태는 [기부 인증 구현 기록](../apps/ios/docs/donation-verification-161.md)을 따른다.

## 운영자 AI 분석 동의 — #252

2026-11-09. 기부 자료를 제출할 때 사용자는 **AI 검사에 동의하고 제출** 또는 **자료만 제출**을 선택한다. 동의문은 제출 파일의 OpenAI 전송과 운영자의 같은 파일 분석을 안내한다. 사용자가 제출 뒤 직접 한 번 검사하는 동의는 운영자에게 별도 권한을 부여하지 않는다.

`20261109005000_oi_evidence_operator_ai_consent.sql`은 소유자가 명시적으로 동의한 경우에만 현재 제출 시각을 함께 기록한다. 기존 자료에는 동의 기록을 소급해 만들지 않는다. 같은 접수 요청의 재시도는 원래 선택을 유지하고 새 파일로 다시 제출할 때는 새 동의가 필요하다. 운영자 함수는 원본을 읽기 전과 OpenAI에 보내기 직전에 권한·제출본·동의를 확인한다. 기존·미동의 자료는 운영자가 직접 검토한다.

운영 적용 시 먼저 새 `analyze-evidence`를 배포해 동의가 확인되지 않는 요청을 막고, 마이그레이션과 본 앱 업데이트를 적용한다. 새 함수는 동의 필드를 조회할 수 있을 때까지 AI 요청을 거부한다. 가상 파일로 자료만 제출·동의 제출·재제출을 각각 검증한다. [개인정보 공유와 명시적 동의 기준](https://developer.apple.com/app-store/review/guidelines/#privacy)
