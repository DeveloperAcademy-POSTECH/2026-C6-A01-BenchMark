# 보관·삭제 기준 확인 — #208

## 확정 범위

2026-11-07 사용자 결정: 현재 방식인 **계정 유지 중 보관, 탈퇴 시 삭제**를 유지한다. 임의의 30/90일 자동 만료나 탈퇴 후 증빙·신고 별도 보관 정책은 만들지 않는다. `README.md`의 공개 처리방침을 이 기준과 실제 저장 위치에 맞춘다. 본 앱·Clip의 처리방침 링크는 main의 README를 가리키므로 이 PR의 내용은 main 반영 이후 공개 안내에 적용된다.

## 구현 근거

| 대상 | 코드에서 확인한 경계 |
| --- | --- |
| 서버 탈퇴 | `supabase/functions/delete-account/handler.ts`: 현재·최근 OAuth 본인 확인, `prepare`의 소유 파일 목록을 Storage API로 삭제, 파일이 없어진 뒤 `finish`. 실패 시 완료 응답을 주지 않는다. |
| 계정 데이터 | `20261105164932_oi_account_deletion.sql`: 해당 계정과 연결된 로그인, 이야기·사진·수집·증빙 이력·작성 승인·관련 감사 기록을 삭제. 무관한 사용자 자료는 유지한다. 일반 `delete_story`는 `status=deleted`의 논리 삭제이므로 공개 중단과 탈퇴의 물리적 행 삭제를 안내에서 구분한다. |
| 증빙 해시 | `20261105131031_oi_evidence_fingerprints.sql`: 증빙 요청 삭제에 따라 해시가 cascade 삭제된다. 재제출로 원본 경로·제출 시각이 바뀌면 이전 해시도 제거한다. |
| 콘텐츠 신고·제재 | `20261106150000_oi_content_safety.sql`: 신고자 member 또는 대상 이야기 삭제에 따라 신고 삭제, 대상 member 삭제에 따라 제한 삭제. 탈퇴한 검토자의 다른 신고 처리자 FK는 null 처리한다. |
| 학교 자료 | `analyze-school-evidence/handler.ts`: 이미지/PDF는 요청 처리 중 분석. DB·Storage 저장 호출 없음. 결과는 클라이언트가 계정별 기기 요약으로 저장하며 공식 소속 인증·자동 운영자 접수가 아니다. |
| AI 전송 | `_shared/document-analysis.ts`: OpenAI Responses API에 `store: false`. 이 설정은 외부 사업자의 오남용 방지 로그까지 즉시 삭제하는 보장이 아니다. |
| 기기 계정 자료 | `OiRemoteStore.clearDeletedAccount` → `OiDraftVault.purgeAccounts`: 탈퇴 영수증의 모든 연결 계정 폴더와 외형 설정, 세션을 삭제. 기기 자료 삭제 실패 시 재시도 기록을 유지한다. 다른 기기의 로컬 사본을 원격 삭제하지 않는다. |
| 기기 독립 자료 | `StoryCollectionStore`, `OiContentSafetyStore`: 계정과 별개인 App Group 카드/차단 목록. 각 삭제·차단 해제 UI로 관리하며 계정 탈퇴에 자동 연동된 것으로 안내하지 않는다. |
| 위치 | 기기의 위치는 주변 판정·AR에 사용. 이야기 배치 시 선택 좌표는 서버 저장 대상. 카드 요청 RPC에는 story/request ID를 보내며 현재 GPS 좌표를 보내지 않는다. |

## 검증

- 격리 PostgreSQL에서 전체 마이그레이션과 계정 통합·삭제 회귀 검사를 수행해 통과했다. 삭제 검사에 신고자 탈퇴/신고 대상 이야기 삭제 두 경우, 연결 계정의 작성 제한, 증빙 해시, 관련 감사 기록 삭제 및 무관한 감사 기록 보존을 추가했다. 검사 후 임시 PostgreSQL의 프로세스·소켓을 정리했다.
- `node --test supabase/tests/account-deletion.test.mjs`: 4개 통과. 파일 삭제 완료 전 Auth 종료 금지, 실패·외부 계정 증명·동의 및 최근 인증 경계를 확인했다.
- 테스트는 합성 계정·대체 HTTP 응답으로 수행한다. 운영 사용자 탈퇴나 실제 개인정보·기부 증빙 전송은 하지 않는다. 삭제 구현과 서버 설정은 변경하지 않으므로 새 운영 배포는 필요하지 않다.

## 외부 자료와 운영 확인

- [OpenAI 데이터 관리](https://developers.openai.com/api/docs/guides/your-data), 2026-11-07 확인: API 오남용 방지 로그는 기본 최대 30일, 법령·안전 관련 예외가 있다. 실제 조직의 Zero Data Retention 또는 별도 보관 계약은 확인하지 않았으며 적용된 것으로 약속하지 않는다.
- [Supabase 백업](https://supabase.com/docs/guides/platform/backups), 2026-11-07 확인: 백업 보관은 요금제/설정에 따라 다르며 DB 백업에는 Storage 파일 자체가 포함되지 않는다. 운영 프로젝트의 백업·PITR 설정이나 별도 오프라인 백업을 변경하지 않았다. 운영팀은 실제 설정과 운영 로그 보관 범위를 확인해 외부 공급자 안내와 함께 관리해야 한다.
- 운영팀 확정 필요: 신고 처리 담당자·목표 응답 시간, 이메일로 받은 비공개 문의 자료의 처리·삭제 절차. 계정에 연결되지 않은 메일을 DB의 탈퇴 cascade로 삭제한다고 약속하지 않는다.
- App Store Connect 개인정보 응답은 별도 제출 항목이다. 현재 구현의 계정·사진/사용자 콘텐츠·증빙(금융/학적 자료 포함 가능)·위치 저장 범위를 기준으로 팀이 확인해야 한다. 이번 작업은 메타데이터 제출이나 앱 업로드를 수행하지 않는다.
