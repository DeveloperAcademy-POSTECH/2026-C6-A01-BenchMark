# 기부 인증 화면과 즉시 AI 참고 검사

2026-11-05, 이슈 #161. [Figma 기부 인증 뷰](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2911-752)를 기준으로 구현한다. 11월 4일의 증빙 화면 보류를 이번 사용자 요청 범위에서 해제한다.

## 화면과 동작

- 설정 → 기부 인증, 이야기 목록 → 작성 승인 안내 → 기부 인증하기에서 진입한다.
- 사진 보관함 또는 파일 앱에서 JPEG·PNG·PDF를 고른다. 사진은 기존 이미지 처리기로 JPEG로 준비하고 파일은 10MB 제한과 시그니처를 검사한다. 선택만으로 전송하지 않는다.
- ‘인증 요청’에서 비공개 제출 및 OpenAI 전송 동의를 확인한다. 기존 `submitEvidence`와 보호된 기기 재시도 기록을 재사용한다. 반려·보완 요청 행을 선택하면 기존 신청에 재제출한다.
- 접수 성공 후 즉시 본인 제출본의 AI 참고 결과를 보여준다. 검사만 실패하면 신청/파일을 중복 생성하지 않고 해당 제출본만 다시 검사한다. 원본 제출 중단은 기존 작업 식별자로 재개한다.
- AI 결과는 현재 화면의 메모리에만 보관한다. 화면 이탈·계정 전환·재인증 요구 시 선택 파일/결과를 해제한다. 서버 업로드는 기존 비공개 증빙 저장 정책을 따른다.
- `pending`은 검토중, `changes_requested`는 보완 요청, `rejected`는 미충족, `approved`는 작성 승인, `revoked`는 승인 철회로 구분한다. 접수만으로 작성 승인을 표시하지 않는다.

## 디자인 근거와 차이

기준 프레임은 402×874pt다. 상태바·홈 인디케이터는 시스템이 담당한다. 첨부 영역은 좌우 25pt·최소 높이 180pt·반경 30pt, 버튼 간격 8pt·반경 22pt, 진척도는 좌우 20pt·제목 24pt, 본문 16pt다. 작은/큰 화면에서는 가로 여백을 유지하고 내용을 스크롤한다. 접근성 글자 크기에서는 버튼과 날짜/상태를 세로 배치한다.

버튼 원본 `3739:3608/3609`·`3739:3610/3611`의 색상·문자·상태를 확인해 SwiftUI `Button`으로 구현했다. 승인 배지 `3739:3495`의 배경과 씨앗 원본을 `DonationApprovalBackground`·`DonationSeed`로 번들에 포함했다. 씨앗 이미지는 Figma 원본의 crop/scale을 적용한다. 시스템 뒤로가기는 원본 SF Symbol `chevron.left`를 사용한다. 미확보 에셋을 임의 대체하지 않았다.

동작에 필요한 차이는 다음과 같다.

- 버튼 높이는 42pt 시안보다 2pt 큰 최소 44pt로 누름 영역을 확보한다. 기본 화면의 진척도 제목은 약 452pt부터 시작한다.
- 상단 씨앗 그림 옆 숫자는 보상 재화가 아닌 실제 작성 승인된 증빙 건수다. 접근성 이름도 이를 명시한다. 최소 기부액·씨앗 지급·코인 정책을 추가하지 않는다.
- Figma의 예시 건수/날짜 대신 서버 건수/제출일을 표시하고, 없는 날짜를 추정하지 않는다. 일시는 한국 시간과 한국어 달력으로 표시한다.
- 첨부 후 이름/미리보기, 동의창, AI 결과·에러·빈 목록은 현재 기능에 필요한 상태로 기존 글꼴/컴포넌트와 네이티브 대화상자를 사용한다.

## API 계약

`POST /functions/v1/analyze-donation-evidence`

- 사용자 JWT, JSON `{ "evidence_id": "<본인 pending 신청 UUID>" }`만 받는다.
- 기존 Supabase 사용자 JWT와 RLS로 자료를 읽고, `user_id`와 Storage 소유자 prefix를 별도로 검증한다. 익명 계정·다른 사용자 자료·현재 제출본이 아닌 자료는 거부한다.
- 기존 `_shared/document-analysis.ts`의 `analyzeDocument`·프롬프트·모델·10MB 검증·strict 응답·60초 제한을 그대로 재사용한다. 기존 운영자 API는 유지한다.
- 반환 전 세션·소유권·상태·경로·제출 시각을 다시 확인한다. 앱도 신청 ID와 제출 시각을 대조하고 진위 인증/자동 승인 응답을 거부한다.
- 결과는 `review_type: donation_evidence`, `human_review_required: true`, `authenticity_verified: false`와 기존 assessment다. DB/Storage/작성 권한을 변경하지 않는다.
- 동일 isolate의 동시 3건·사용자별 분당 5회 제한은 분산 비용 한도가 아니다. 자동 재시도하지 않는다. 결과나 증빙 바이트를 로그에 남기지 않는다.

## 검증 및 배포

- `npm --prefix supabase test`: 87개 통과. 소유권·세션·재제출 경합·형식·공급자 실패·호출 빈도와 기존 운영자/학교 분석 회귀 포함.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-oi-service-checks.sh`: 통과.
- Xcode 27.1, 기존 Swift 5 언어 모드·iOS 26.2 타깃을 유지한다. 로컬 프로젝트/서명 설정은 커밋에 포함하지 않는다.
- `OiFlowChecks`의 `OiRemoteStoreTests`, `OiSchoolEvidenceContractTests`, `OiFigmaFidelityVisualTests/testDonationEvidenceCaptures`: iPhone 17 Pro / iOS 26.5에서 60개 통과. 최종 검증 결과는 PR에 기록한다.
- 402×874·375×667·440×956·접근성 최대 글자 크기 및 첨부/AI 결과/AI 오류 10개 [캡처](verification/donation-verification-161)를 확인했다. 각 캡처의 숨은 창까지 분리·해제했는지 기존 검사로 확인한다.
- 중간 재실행에서 Simulator `Busy / Application failed preflight checks`가 발생했다. 동일 시뮬레이터가 종료된 상태임을 확인하고 명시적으로 부팅을 완료한 뒤 최종 60개 테스트를 다시 통과했다. 최종 결과: `/tmp/benchmark-donation-verified-tests.xcresult`.
- `npm --prefix supabase run check`: 로컬 Deno 미설치로 실행 실패(`deno: command not found`). CI의 Deno 검사로 별도 확인한다.

2026-11-05 사용자 승인 후 기존 `52gibu` 프로젝트(`kfzfzarslqdqmrazohej`)에 `analyze-donation-evidence` v1을 배포했다. 원격 상태 `ACTIVE`, `verify_jwt: true`를 재조회했고, 인증 없는 POST가 HTTP 401로 차단됨을 확인했다. 기존 서버 `OPENAI_API_KEY`·`OPENAI_EVIDENCE_MODEL`을 읽으며 값을 변경하지 않는다. 스키마 마이그레이션이나 새 클라이언트 비밀키는 필요 없다. 실제 로그인 사용자의 증빙 제출·과금되는 AI 응답은 이번 자동 검증에서 실행하지 않았다.

서버 비밀 설정의 이름만 조회해 `OPENAI_API_KEY` 존재를 확인했다. `OPENAI_EVIDENCE_MODEL`은 설정돼 있지 않아 기존 분석 엔진 기본 모델 `gpt-4.1-2025-04-14`를 사용한다. 키 값과 digest는 출력·저장하지 않았다.

Needs confirmation:
- 실제 계정의 자료 제출 → AI 응답 → 운영자 작성 승인 전체 흐름과 개인정보 보관·삭제 운영 정책.
- AI 결과는 원본 진위·실제 납입을 보증하지 않는다. 자동 테스트는 탐지 정확도 평가가 아니다.
