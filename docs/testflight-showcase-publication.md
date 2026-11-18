# 금요일 쇼케이스 TF 이야기 공개 임시 패치 — #508

2026-11-18 사용자 요청. **2026-11-20 금요일 쇼케이스용 한시 예외이며 정식 검수 정책이 아니다.** 쇼케이스 이후 원복한다. 자동 종료 시각을 임의로 정하지 않으며, 행사 종료 후 아래 스위치를 끄고 임시 앱 코드를 제거한다.

## 동작

- Release 앱은 `AppTransaction.shared`로 Apple이 검증한 Sandbox 앱 거래를 확인한 경우에만 즉시 심기를 허용한다. Debug·Simulator와 Production 앱 거래에서는 기존 AI 검수 조건을 유지한다. 검증 실패 시 기존 경로를 사용한다.
- `농장에 오이 심기` → 기존 심을 오이 선택 → `농장에 오이 심기`로 등록한다. 미검토·AI 거부·검수 결과 조회 실패 여부를 심기의 조건으로 사용하지 않는다.
- `내용 검토 요청하기`, `검토 전`, `검토중`, `게시 가능`, `수정 필요` 등 기존 UI를 유지한다. 검토 버튼은 기존 AI 검수를 계속 요청한다. 즉시 심기는 OpenAI에 전송하거나 가짜 검수 승인 결과를 저장하지 않는다.
- 기기 전용 초안도 기존 저장·사진 순서·삭제 반영·외형·카드 양면/표지 준비를 거쳐 등록한다. 실패하면 초안은 보존하고 오류를 표시한다. 응답 유실은 서버의 ID·작성자·리비전·공개 상태·외형·카드를 확인해 복구한다.
- 로그인, 유효 세션, 소유권, 작성 중지, 계정 제한, 입력·위치·첨부·카드·이어진 이야기 검사는 유지한다. 공개한 글은 일반 App Store 앱을 포함한 공용 공개 목록·카드·AR에서도 조회된다.
- `publish-showcase-story`는 Apple 공식 서버 라이브러리 3.1.0으로 서명·Apple Root CA - G3 인증서 체인·앱 번들 ID·Sandbox 환경을 검증한다. 자체 선언한 TF 플래그나 미검증 JWT는 허용하지 않는다. 인증서 원문은 공개 신뢰 루트이며 앱 서명용 인증서·개인키가 아니다.

## 적용 순서

이 PR 자체는 운영 DB·함수 배포·TF 업로드를 수행하지 않는다.

1. `20261118130803_oi_testflight_showcase_publication.sql`을 검토한 뒤 대상 서버에 적용한다. `testflight_showcase_enabled`는 기본 `false`다. 기존 일반 공개 RPC의 AI 조건을 변경하지 않는다.
2. `publish-showcase-story`를 기존 프로젝트에 배포한다. 기존 JWT 검증을 유지한다. Supabase 기본 환경변수 외 신규 비밀키는 필요 없다. 함수별 `deno.json`의 고정된 Apple 라이브러리 버전을 사용한다.
3. 패치 포함 Release 빌드를 TestFlight로 제공한다. 유효 TF 설치에서 실제 Apple Sandbox 앱 거래가 검증되는지 확인한다.
4. 쇼케이스 운영 시 아래 값을 명시적으로 켠다.

```sql
update benchmark_private.oi_story_creation_settings
set testflight_showcase_enabled = true where singleton;
```

5. 실제 TF 기기에서 검토 전 초안을 심고 다른 계정의 공개 지도·카드에서 확인한다. 검수 거부 초안도 확인한다. 기존 App Store 설치의 미검토 심기는 계속 차단되는지 별도로 확인한다.

## 원복

먼저 다음 스위치를 끈다. 기존 TF 설치의 즉시 심기는 서버에서 실패 처리되며 초안은 보존한다. 이미 공개한 이야기를 자동 비공개로 바꾸지 않는다.

```sql
update benchmark_private.oi_story_creation_settings
set testflight_showcase_enabled = false where singleton;
```

이후 앱의 `OiTestFlightShowcase`, `showcaseTransaction`/`publishForShowcase` 분기, 목록의 `showcaseSelection` 분기 및 전용 API를 제거한 빌드를 제공한다. 전용 Edge Function을 제거하고 `oi_publish_showcase_story(uuid,uuid,jsonb)` 실행 권한을 회수한다. DB 함수·컬럼과 pending 처리 확장의 물리적 제거는 새 순방향 마이그레이션으로 정리한다. 이미 적용한 마이그레이션을 삭제·수정하지 않는다. 원복 앱에서는 기존 AI 검수 통과 후 심기를 다시 사용한다.

## 검증 경계

로컬 SQL은 전체 마이그레이션 적용 후 전용 공개 RPC와 일반 AI 공개 조건을 확인한다. Edge 테스트는 인증·서명 검증 전 공개 차단·DB 오류 전달·OpenAI 미호출을 확인한다. iOS 테스트는 의존성을 주입해 TF·일반 분기와 실제 목록 심기→사진·카드 준비→공개를 확인한다. Release StoreKit 코드는 iPhoneOS SDK로 별도 타입 검사한다.

Needs confirmation:
- 실제 TF 서명 거래의 온라인 인증서 확인, Edge 런타임 배포와 기기 등록·타 계정 공개 조회는 로컬 테스트만으로 증명되지 않는다.
- Sandbox 앱 거래는 Supabase 계정과 직접 결합된 증명이 아니다. 유효 TF 거래를 가진 이용자에 대한 임시 허용이며, TF 배포 대상과 서버 스위치를 함께 관리한다.

근거: [Apple AppTransaction](https://developer.apple.com/documentation/storekit/apptransaction), [Apple 서버 서명 검증 라이브러리](https://github.com/apple/app-store-server-library-node), [Supabase 함수 의존성](https://supabase.com/docs/guides/functions/dependencies).

## 2026-11-18 운영 적용 및 코인 후속 — #516

운영자·일반 사용자 모두 TF에서는 검수 없이 심을 수 있어야 한다는 사용자 재확인에 따라 미배포 서버 작업을 완료했다. 코인 wrapper가 새로 추가했던 운영자 직접 게시 PT426도 제거했다. 기존 운영자 권한·현재 제출본·감사 기록 검사는 delegate에 유지한다.

- 프로젝트: `52gibu` (`kfzfzarslqdqmrazohej`).
- 적용 이력: `20261118130803_oi_testflight_showcase_publication`, `20261118130822_oi_restore_operator_coin_publication`.
- 기존 TF 마이그레이션은 운영에 미적용 상태였으며, 실제 운영 base가 저장소의 pending 허용 anchor와 달라 최초 시도는 롤백됐다. 캡처한 실제 base 해시와 단일 draft guard를 검증하는 분기를 추가한 뒤 로컬 양쪽 이력 검증 후 적용했다. 파일 시각은 실제 운영 이력과 일치시켰다. 이미 운영에 적용된 코인 마이그레이션은 수정하지 않는다.
- Edge: `publish-showcase-story` v1 `ACTIVE`, `verify_jwt=true`; Apple 공식 검증 라이브러리·신뢰 루트와 기존 세션·소유권·작성 중지·첨부 검사를 유지한다.
- `testflight_showcase_enabled=true` 확인. `auto_moderation_enabled=true`는 일반 빌드/선택 검토 경로를 위해 유지한다.
- 공개 RPC 실행 권한: service_role=true, authenticated=false, anon=false. 코인 wrapper의 추가 PT426 제거와 무제한 계정3개 보존 확인.
- TF 일반 사용자도 최초 공개30코인, 재심기0코인, 지정 무제한 계정0코인. 잔액 부족은402로 전달한다. 버튼은 Figma 원본의 제목 + 코인 이미지 + `$ 30` 구조이며, 일반 계정은 TF에서도 비용 확인 후 진행한다.
- iOS 선택6개, Node21개, 전체 SQL harness 통과. 실제 운영 base를 fixture로 재현해 일반/무제한 TF 공개·최초 차감·재게시 무료·운영자 기존 공개 권한을 확인했다.

Needs confirmation:
- 실제 TF 기기에서 Apple 서명 거래 온라인 검증과 타 계정 공개 조회는 수행하지 않았다. 코드·주입 테스트와 서버 활성화 확인을 실기기 완료로 간주하지 않는다.
- 버튼 문구 변경은 이 패치를 포함한 새 앱 빌드에 적용된다. 이 작업은 TF 업로드 또는 PR 병합을 수행하지 않는다.
