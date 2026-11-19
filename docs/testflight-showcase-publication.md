# 쇼케이스 설치본 검토 없는 즉시 공개 — #508·#516·#527

**2026-11-19 사용자 최종 결정: TF·internal test·직접 설치·Debug/Release 구분 없이, 이 패치가 포함된 설치본은 검토 없이 게시한다.** 2026-11-20 금요일 쇼케이스용 요구사항이다.11월18일의 TF 전용 경계는 대체됐으며 AppTransaction/Sandbox/JWS를 게시 조건으로 사용하지 않는다.

## 현재 동작

- `농장에 오이 심기` → 저장한 오이 선택 → `농장에 오이 심기`로 공개한다. 검토 전·거부·검토 결과 조회 실패도 같은 경로를 사용한다.
- 심기 버튼은 로딩·빈 목록·처리 중에도 항상 표시하고 활성화한다. 빈 목록·로그인·진행 중 탭은 안내하며 중복 게시 요청은 보내지 않는다.
- `내용 검토 요청하기`와 검토 상태 표시는 유지하지만 선택 기능이다. 심기는 AI를 호출하거나 승인 결과를 만들지 않는다.
- 기기 초안도 기존 입력/사진 업로드·순서/삭제·오이 외형·카드 양면/표지 준비를 사용한다. 실패 시 초안을 보존하고 응답 유실은 ID·작성자·리비전·공개 내용으로 복구한다.
- 로그인·실제 세션·소유권·제한 계정·작성 중지·입력·위치·첨부·이어진 이야기 검증은 유지한다. 최초30코인·재심기0·지정 무제한0 규칙도 유지한다.

## 서버 계약과 적용

- 프로젝트 `52gibu` / `kfzfzarslqdqmrazohej`.
- `publish-showcase-story` **v2 ACTIVE**, `verify_jwt=true`. POST `{submission: ...}`만 필요하며 `app_transaction`은 요구하지 않는다. 예전 클라이언트가 함께 보내는 필드는 무시한다.
- Edge가 Auth의 실제 토큰을 확인한 뒤 서비스 역할 전용 RPC를 호출한다. RPC의 저장된 세션·작성자·현재 첨부/리비전·코인 검사는 유지한다. anon/authenticated에는 RPC 직접 실행 권한이 없다.
- `testflight_showcase_enabled=true`는 기존 컬럼 이름을 유지하는 운영 스위치다. 이제 TF 구분을 의미하지 않는다. `auto_moderation_enabled`는 선택적 검토용으로 유지한다.
- 이번 변경에는 DB 스키마/함수 변경이 없다. 기존 RPC의 서버 스위치와 검증을 그대로 사용하고 Edge의 Apple 거래 요구 조건을 제거했다.

## 검증 기록

- `npm --prefix supabase test`:144개 성공, 실패0. 직접 설치 요청의 거래 필드 생략, 예전 클라이언트 호환, 인증 실패·익명·위조 주체·유효 세션 누락 차단, 402/403/409/422/503 전달을 확인했다.
- iOS와 실제 기기 설치 결과는 [검증 기록](verification/plant-button-527/README.md)에 최종 결과를 추가한다. 이전의 TF 거래를 주입한 테스트를 최종 증거로 사용하지 않는다.
- [이전 #516 화면 픽셀 비교](verification/figma-story-list-516/README.md)는 레이아웃·에셋 근거이며 당시 TF 제한 설명은 현재 정책이 아니다.

## 원복

행사 후 서버 스위치를 끄면 새 즉시 공개를 중단한다. 이미 공개된 이야기를 자동 비공개로 바꾸지 않는다. 종료 시각은 임의로 정하지 않는다.

```sql
update benchmark_private.oi_story_creation_settings
set testflight_showcase_enabled = false where singleton;
```

이후 검토 정책과 앱 심기 경로의 전환은 별도 사용자 결정에 따른다. 이미 배포한 마이그레이션을 수정/삭제하지 않는다.

## 이전 적용 이력

11월18일 #508/#516은 TF 전용 AppTransaction 검증과 서버 RPC를 배포하고 코인 규칙을 통합했다. 운영 base와 저장소 AI base 차이를 검증한 마이그레이션 `20261118130803_oi_testflight_showcase_publication`, 코인 wrapper 후속 `20261118130822_oi_restore_operator_coin_publication`은 그대로 보존한다.11월19일 최종 요청으로 TF 전용 경계를 제거했다.
