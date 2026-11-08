# 오이기부 1.0.0 스토어 설명과 심사 메모 — #234

이 문구는 #234의 DB·앱을 모두 반영한 빌드용이다. [이전 빌드의 스크린샷·메모 보관본](https://github.com/DeveloperAcademy-POSTECH/2026-C6-A01-BenchMark/pull/233)은 당시 화면을 기록한다. 라이브 등록 정보는 최종 빌드와 실기기 검증에 맞춰 갱신한다.

## 스토어 설명 — 한국어

POSTECH 캠퍼스에서 이야기를 읽고, AR로 오이를 찾아 카드를 모아보세요. 내 이야기도 오이에 담아 캠퍼스 지도에 남길 수 있어요.

- **캠퍼스 탐색:** 3D 지도에서 오이를 골라 그 장소에 남겨진 공개 이야기를 읽어요. 현장에서는 카메라로 오이를 찾고 카드를 모을 수 있어요.
- **이야기 남기기:** 로그인한 뒤 이야기와 사진을 더하고, 오이와 카드를 꾸며 배치할 장소를 정해요. 운영팀이 이야기를 검토한 뒤 지도에 공개해요. 세부 꾸미기는 기기에서 미리 볼 수 있고, 공개 화면에는 기본 디자인이 표시돼요.
- **체험하기:** 홈에서 예시 이야기를 읽고 현장 방문 없이 AR 수집을 체험해 보세요. 체험에서 얻은 카드는 실제 도감에 기록되지 않아요.
- **나만의 농장:** 모아 둔 카드를 다시 보고 농부 캐릭터를 꾸며 보세요.

기부는 선택이에요. 기부하거나 자료를 제출하지 않아도 이야기를 남기고 오이와 카드를 이용할 수 있어요. 기부를 원하면 POSTECH 공식 기부처를 이용해 주세요.

## App Review notes — English

OiDonation is a free iPhone app for discovering and sharing stories on the POSTECH campus. Donating, submitting donation evidence, or earning a reward is never a condition for creating a story, placing a character, or collecting a card. The app does not accept payments. The optional donation link opens POSTECH’s official website in a browser. Optional evidence review in settings is private and does not grant app functionality or change story publication.

**Try the sample story and AR collection without an account or a campus visit.** On the main map, tap **체험하기** (Try it) → **6냥이오이** → **스토리 보기** (Read story) → **수집하기** (Collect) → **시작** (Start). On an AR-capable iPhone, allow camera access, find three cucumber characters within 30 seconds, and tap **체험 카드 모으기** (Collect sample card). Sample cards are separate from the account collection. In the App Clip, **이야기·AR 체험** (Try story and AR) opens the same experience.

**Try story creation.** Open **MY → 설정** (Settings) and sign in with Apple or Google using the review access supplied in App Store Connect. Return to the map and select **+ → 오이 만들기** (Create cucumber). Accept the story and moderation rules, enter a title and story, add 1–3 test photos, select a campus location, and name the cucumber when editing its card. Preview and submit the story for review. A pending story remains private until a content moderator approves it. Detailed appearance edits stay in the device preview; the public map and card use the available presets. No donation or evidence is required for any of these steps.

**Try account deletion.** Open **MY → 설정 → 회원 탈퇴** (Delete account) and reauthenticate with the same provider. Use a separate disposable account if the story-creation account needs to stay available for review.

## 등록 전 확인

- 실제 로그인 가능한 일반 심사용 접근을 준비해 기기에서 확인하고, 자격 증명은 App Store Connect의 비공개 입력란에만 적는다. 예시 체험은 로그인 기능 검증을 대신하지 않는다.
- [출시 확인 목록](release-preflight.md)에 따라 스크린샷을 최종 화면과 대조하고 App Clip 기본 경험이 활성화된 호출 URL을 확인한 뒤 심사 메모에 추가한다. 공개 지도·카드에 세부 꾸미기가 표시되는 것처럼 설명하지 않는다.
- [Apple 심사 가이드라인 3.1.1](https://developer.apple.com/app-store/review/guidelines/#payments)과 [3.2.2(iv)](https://developer.apple.com/app-store/review/guidelines/#other-business-model-issues)를 기준으로 기부가 기능이나 콘텐츠를 열어 주지 않는지, 공식 수납이 앱 밖에서 이뤄지는지 점검한다.
