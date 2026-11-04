# iOS 제품 앱 정리 — 2026-11-04 / #141

[Figma 프로토타입 ver.2](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2339-2109)를 기준으로 iOS 본 앱과 App Clip의 진입점을 정리했다. 지도는 POSTECH을 표시한다. 집 → MY 작업실 → 설정에서 로그인과 로그아웃, 닉네임, 학교, 기기 권한을 다룬다. 지도 `+`, 내 농장과 이야기 목록에서 실제 작성·초안 복원·이야기 관리를 이용한다. 공개 이야기의 현장 AR과 수집 게임, App Clip의 기본 진입과 기기 수집 로직을 유지했다. 공개 이야기로 여는 링크는 승인된 호스트 연결이 필요하다. [빈 상태와 미정 화면](empty-state-inventory.md)

지도 봉투는 받은 카드 요청을 표시한다. 공개 이야기 소유자만 수락·거절할 수 있으며 DB에 상태를 기록한다. 도감 저장이나 이야기 변경은 발생하지 않는다. 요청은 자동 만료·삭제되지 않는다. iOS 발송 화면과 수락 후 제품 동작은 결정되지 않아 제공하지 않는다. [서버 마이그레이션](../../../supabase/migrations/20261104090627_oi_card_requests.sql)

| 운영 앱에서 호출되지 않는 기능 | 확인 범위 |
| --- | --- |
| 학교 소속 증빙 AI | 별도 [Draft PR #140](https://github.com/DeveloperAcademy-POSTECH/2026-C6-A01-BenchMark/pull/140)의 기능이다. 이 작업의 앱 진입점이나 마이그레이션에 포함하지 않는다. 설정의 학교 선택은 기존 프로필 편집이다. |
| 기부 증빙 제출·보완·재시도 | #141 전부터 앱 화면을 보류했다. `OiRemoteStore.submitEvidence`와 `retryEvidence`, 서버 저장·심사 경로를 유지한다. [기부 흐름](../../../docs/supabase-flow.md) |
| 로그인 수단 추가·계정 통합 | 계정 화면 제거로 앱 진입이 끊겼다. `OiAccountMergeView`의 미리보기와 테스트, 기존 통합 계정의 인증·데이터 귀속, 서버 계약은 남아 있다. [계정 통합](../../../docs/account-merge.md) |
| 운영자 이야기 공개 승인·비공개 전환 | 계정 화면의 운영자 검토 UI가 사라졌다. `review_story` 서버 동작과 운영 권한은 남아 있다. 일반 사용자의 내 이야기 수정·삭제와 검토 요청은 유지한다. [서비스 저장소](../OiDonation/Features/Profile/OiRemoteStore.swift) |
| 제출한 이야기의 기기 보관본 목록 | 계정 화면의 보관본 목록을 제거했다. 기존 파일은 보존한다. 미제출 초안과 파일 읽기 오류 안내는 실제 이야기 목록에서 처리한다. [이야기 목록](../OiDonation/Features/Profile/OiStoryListScreen.swift) |
| 옷장 현장 테스트 | 지도 길게 누르기와 작성 중 테스트 배치 버튼을 제거했다. 기기 저장소 로직과 이미 저장된 시험 사본은 남아 있으며 실제 옷장·카드 편집은 계속 사용한다. [옷장](../../../docs/wardrobe-customization.md) |
| 사진 테스트·NFC 쓰기·단독 촬영·주변 AR | 기존 앱 메뉴에서 진입할 수 없다. 사진 콜라주 소스와 검사는 `apps/ios/Tests/PhotoTest`에서 확인한다. NFC 태그 쓰기와 App Clip의 링크 처리 로직은 별도다. |
| 기존 벤치 후원·참여·명패 미리보기 | `SponsorshipView`에서 참여와 명패로 이어지지만, 현재 앱 루트에서 후원 화면을 여는 호출부가 없다. |
| 카드 요청 생성 API | 서버에 요청을 넣는 `oi_request_card`를 제공한다. iOS 화면은 받은 목록을 읽고 수락·거절만 한다. [서버 마이그레이션](../../../supabase/migrations/20261104090627_oi_card_requests.sql) |

작성 체험, 옷장 바로 체험, 예시 오이 탐색, 앱 실행 인자로 열던 디버그 화면은 제거했다. Xcode 미리보기와 테스트 타깃은 분리해 사용한다.

Needs confirmation:

- 카드 요청 보내기 진입점, 수락 후 도감/권한 동작, 만료 정책. 현재 수신함만 제공한다.
- 기부 증빙 화면, 학과·학번·이름 편집, 티켓·코인 경제는 이번 작업에서 연결하지 않았다. 설정의 학교 선택과 기존 작성 승인 검증은 동작한다.
- 카드 꾸미기의 크기·패턴·테두리와 농부의 개별 옷·포즈·3D 꾸미기는 동작이 없어 제품 화면에 추가하지 않았다. 도감의 `MY` 칩, 독립 오이코드, 이어진 기부 관계의 계약도 기존과 같이 미정이다.
- 운영자 검토를 사용할 실제 도구와 신규 사용자의 작성 승인 부여 경로.
- 공개 이야기 링크에 사용할 승인 호스트와 공개 카드 이미지 공급 계약. 운영 계정으로 하는 Google·Apple 로그인, 요청 수신·결정, iPhone 현장 AR 및 공개 App Clip 호출 확인. [App Clip 연동](app-clip-ar-collection.md)

검증 화면은 모두 가상 테스트 데이터로 렌더했다. [받은 요청](verification/product-141/card-requests-inbox-402x874.png), [빈 요청함](verification/product-141/card-requests-empty-402x874.png), [최대 접근성 글자 크기](verification/product-141/card-requests-inbox-accessibility5.png), [MY 설정](verification/product-141/my-settings-402x874.png). 실제 계정이나 운영 데이터는 사용하지 않았다.
