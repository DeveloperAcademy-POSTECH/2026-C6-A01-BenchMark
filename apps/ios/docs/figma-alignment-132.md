# 최신 Figma iOS 정합 — 2026-11-03 / #132

## 기준과 분담

기준은 사용자가 지정한 [프로토타입 ver.2 페이지](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2339-2109)다. 지도 `2876:8316`, 접수·커스텀 `3661:3151`, MY `2876:8320`, 수집 AR `2876:8317`을 읽고 현재 화면에 사용되는 원본 자산을 추출했다. 카드 제작 원본 `3180:4492`와 농부 꾸미기의 레이어 자산은 해당 화면을 구성하는 자료로만 사용한다. Lo-fi·ver.1 또는 다른 카드 시안을 새 화면 기준으로 삼지 않는다.

사용자 요청으로 자산 추출·공통 카드·AR·작성·MY 구현은 #132, 다음 세 파일의 작은 UI 수정은 팀원의 #133으로 분리했다. #132는 아래 파일을 수정하지 않는다.

- `Features/Profile/MYCollectionView.swift`: 도감 글꼴·학교 상세 하단 필터·확대 표시
- `Features/Campus/Search/CampusSearchView.swift`: 코드 검색 입력 문구
- `Features/Support/HomeInformationSheet.swift`: 과거 명패·벤치 기부 안내 문구

## 적용

| 영역 | 변경 |
| --- | --- |
| 지도 | 원본 집 모양 MY 진입점과 38pt 농부·닉네임 칩 분리, 학교/오이 추가 원본 아이콘, 목록 드래그 펼침·접힘. 내부 목록이 맨 위일 때만 아래 드래그로 접어 스크롤을 보존 |
| 요약·상세 | 배경 없는 `#` 태그, `스토리 보기`, 실제 카드 확대, 기부자 소개를 첫 섹션으로 이동, 제목·본문·섹션 글꼴과 간격 조정 |
| 실제 카드 | `OiStoryCardArtwork`가 실제 이름·본문·기부자·날짜·캐릭터로 프레임/텍스처/로고를 합성. 예시 원본 카드 PNG는 예시에서만 사용. 서버 카드 URL을 만들거나 다른 기부자의 카드 이미지를 대신 사용하지 않음 |
| 사진 | 실제 서버 사진도 2열 갤러리·확대 지원. 작성 사진의 400pt 미리보기·도구·선택 테두리·끝 추가 버튼은 기존 자르기/회전/삭제와 연결 |
| 작성·접수 | 승인 안내·실제 `오이 심기` 진입, 발 모양 진행도·약관 재확인, 커스텀 완료 버튼·12개 선택 틀, 실제 메타데이터를 사용하는 검토 접수 결과 |
| 증빙 | 계정에서 독립 인증 화면으로 연결. 실제 건수·상태·보완·재시도와 기존 10MB JPEG/PNG/PDF 제한 유지. 파일 선택·오류·소유 계정은 인증 화면이 관리 |
| MY | 농부 터치→2D 세트 선택·저장/되돌리기, 농장의 실제 소유 이야기 오이 배치, 설정의 실제 계정/학교·권한 상태 카드 |
| 수집 | 본 앱 수집 버튼→기존 30초/3마리 게임→승리 후 명시적 저장. 서버 계정의 수집 영수증을 확인한 경우에만 저장 완료 표시. 게임 성공 자체는 수집 기록을 추가하지 않음 |
| App Clip | 같은 게임과 성공 레이아웃 재사용. 원본 카드 URL 우선, 없으면 실제 이야기 기반 카드. 주황 `#` 태그·210pt 패널·실제 Bold/Light 폰트 포함 |

## 상태·저장 경계

- `RootTabView`의 단일 AR cover가 현장/주변 AR·촬영·수집 게임을 선택한다. 기존 AR 이야기에서 게임으로 이동할 때 이전 뷰를 해제하고, 종료 시 원래 AR 경로로 복귀한다. AR 안의 이어서 기부하기는 cover 종료 후 이야기 목록으로 이동한다.
- `CampusCollectionGameHost`는 로그인 계정 변경 시 게임과 저장 작업을 초기화한다. 저장은 단일 요청 UUID와 계정 소유를 확인하며, 기존 `OiRemoteStore.perform("collect")` 이후 실제 `collections`에 있는지 검사한다. 실패하면 재시도 안내를 표시한다.
- Clip의 도감 보관은 기존 App Group 기기 기록이다. 계정 서버 저장으로 바꿔 표시하지 않고 `이 기기에 보관하기`를 유지한다.
- `MYFarmerAppearanceStore`는 계정 UUID별 기기 설정이다. 미로그인은 기존 농부를 사용하며 저장하지 않는다. Figma의 몸·신발·바지·상의·안경 PNG 5개를 합성한 큐 세트와 기존 농부 세트만 제공한다. 다른 사람의 원본 오이·스토리 또는 서버 프로필을 변경하지 않는다.
- `ARCollectionAssets.xcassets`와 `OiStoryCardAssets.xcassets`를 두 타깃에 공유한다. 카메라·타이머 코드를 복제하지 않는다. 본 앱의 iOS 26.2 타깃을 올리지 않고 iOS 27 투영 API에는 가용성 분기를 둔다.

## 의도적으로 유지한 차이와 미확정 항목

- 코인·티켓 경제, 씨앗 획득/사용, 최소 기부금, 수집 거리·방문 인증·보상은 확정하지 않는다. 코인 표시·1pc 보상·광고 적립을 복원하지 않는다.
- 작성 승인과 공개 승인은 다르다. 제출은 `pending`이며 공개 승인 후 지도/AR에 나타난다. 접수 화면의 삭제/도감 저장을 가짜 접수 성공이나 자동 공개로 연결하지 않는다.
- 사진/위치는 기존 순차 작성·실제 3D 지도·미세 이동을 유지한다. 서버의 닉네임/제목/본문/사진·이야기 개수 계약을 Figma 예시 수치로 바꾸지 않는다.
- 2026-11-04 통합으로 개별 3D 의상·사진/데님 꾸미기를 연결했다. 포즈·카드 패턴과 커스텀 외형의 공유 저장 규격은 미정이다. 꾸미기 값은 계정별 기기 초안, 현장 테스트는 별도 기기 사본이며 공개 프리셋과 분리한다.
- 카드의 희귀도·영향 XP는 확정 데이터가 없으므로 `STORY` 표시와 실제 이야기 정보만 사용한다. 디자인의 `NORMAL`·120 XP 같은 예시 수치를 실제 성과로 표시하지 않는다.
- 학과·학번·실명·기부횟수·공개 농부 외형 계약은 추가하지 않는다. 현재 공개 닉네임과 실제 학교/장소를 사용한다. 권한은 실제 OS 상태와 설정 이동으로 표시하며 가짜 스위치를 만들지 않는다.
- 요청 수락/거절·30일 삭제, 도감 `MY` 칩 의미, 독립 사용자용 오이코드, 이어진 기부 관계는 여전히 `Needs confirmation:`이다. 같은 장소의 이야기를 기부 연쇄로 표시하지 않는다.
- 기존 촬영·사진 테스트·NFC·계정 통합·운영자 검토·초안 복구는 유지한다. 앱 전용 기능이라는 이유로 삭제하지 않는다. 서버·Storage·함수·배포·Figma를 변경하지 않는다.

## 검증

아래 명령은 Xcode 27.1의 `/Applications/Xcode.app/Contents/Developer`를 명시해 실행한다. 저장소의 Swift 언어 모드·타깃은 변경하지 않았다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-campus-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-my-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-oi-service-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-app-clip-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiDonation -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/benchmark-figma-132-build CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug -destination 'platform=iOS Simulator,id=50B942DA-CCBB-40FB-A57D-8EB53BEB45A2' -derivedDataPath /private/tmp/benchmark-figma-132-build -resultBundlePath /private/tmp/benchmark-figma-132-reviewed.xcresult CODE_SIGNING_ALLOWED=NO test
```

본 앱과 포함된 Clip의 Debug Simulator 빌드 및 위 네 회귀 스크립트가 통과했다. `OiFlowChecks`는 40개 테스트가 실패 없이 통과했고, 이 중 7개는 실제 View의 56개 렌더·계정별 농부 선택을 검증한다. 기준 402×874, 작은 375×667, 큰 440×956, 접근성 최대 글자 크기를 포함한다. AR 검증은 아래 명령으로 다시 통과했으며 실제 Clip 번들의 필수 폰트 7개, 실제 카드/이미지 없음/불러오기 실패와 시작·실패·성공 표시를 확인했다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-ar-game-visual-checks.sh 50B942DA-CCBB-40FB-A57D-8EB53BEB45A2 /private/tmp/benchmark-figma-132-ar-final /private/tmp/benchmark-figma-132-build/Build/Products/Debug-iphonesimulator/OiDonationClip.app
```

대표 캡처는 [verification/figma132](verification/figma132)에 보관했다. `map-native.png`, `summary-native.png`, `story-native.png`는 별도 테스트용 시뮬레이터의 실제 앱 캡처다. 나머지는 production View를 격리 fixture로 렌더한 것으로, 실제 서버 기록이나 기부자가 아니다. 예시 카드에 포함된 NORMAL/XP는 원본 디자인 예시이며 실제 이야기 카드는 해당 수치를 만들지 않는다.

검토 중 공통 카드의 캐릭터가 내부 레이아웃 크기를 늘려 머리글·하단을 자르는 문제를 수정했다. 큰 글자의 진행 표시는 네 발자국 대신 현재 단계와 이전 버튼을 세로로 배치해 잘림을 막았다. Debug 요약 검증 진입은 홈을 즉시 push하는 대신 대상 화면만 만들어, 아직 표시되지 않은 홈의 3D 렌더러가 함께 생기는 검증 경합을 없앴다. 요약 지도의 메시와 카메라가 정상이고 단독 앱에서 실제 캠퍼스가 표시됨을 확인했다. 일반 사용의 홈→요약 전환까지 실기기에서 검증한 것은 아니다. 지도 로드 오류에는 실제 재시도 안내를 추가했다.

실행 자원은 전용 시뮬레이터 `BenchMark Figma 132`와 빌드/테스트 또는 해당 앱으로 최대 2개 그룹을 사용했다. 테스트 창은 key 상태를 바꾸지 않았고 숨은 창까지 scene에서 분리됨을 검사했다. 임시 진단 코드는 제거했다. 최종 검증 후 본 앱/AR 검증 앱 종료, 검증 앱 제거, 전용 시뮬레이터 종료·삭제와 목록 부재를 확인했다. 사용자 시뮬레이터·앱은 변경하지 않았으며 남겨 둔 실행 자원은 없다.

시각 테스트는 실제 production View와 격리된 fixture/URLProtocol을 사용한다. 창을 만들 때 기존 창의 표시·key 상태를 보존하고, 렌더 후 숨은 창과 RealityKit을 해제한다. 이미지 파일 존재만으로 디자인 일치를 판정하지 않고 대표 렌더를 직접 검토한다.

Needs confirmation: 실제 iPhone 카메라·AR 게임 플레이·야외 위치 정확도, 실제 계정 로그인·증빙 업로드·운영자 공개 승인·다른 기기 동기화는 이번 자동/시뮬레이터 검증으로 확인하지 않았다.

## 2026-11-04 실기기 피드백 반영

- 지도 정면 `3294:3164`의 작업실 버튼은 100pt 원형 안에서 집 이미지를 마스킹하고, 원 밖 2pt 테두리를 그린다. 학교 버튼은 195×42와 `POSTECH 농장`을 적용했다. 지도에 떠 있던 계정·예시 진입은 학교 버튼의 길게 누르기 메뉴에서 접근할 수 있다.
- 지역 재검색은 원본 `2379:4041`의 접힌 지역 목록에서만 노출한다. 전체 지도와 펼친 목록에서는 표시하지 않는다. 목록 열기와 닫기는 `2404:4472`, `3597:4211`의 400ms Ease Out에 대응하며 동작 줄이기를 반영한다. 지도 마커 바탕은 원본의 60% 불투명도를 사용한다.
- 데이터가 로드된 뒤 자동으로 갱신할 때 상태 배너를 숨긴다. 최초 로딩·연결 오류·재인증은 해당 상태에서 안내한다.
- 증빙 첨부·재제출·진척도·심사·관련 동의를 실제 iOS 사용자 경로에서 보류했다. 증빙 처리 로직과 기존 작성 승인 확인·이야기 공개 검토는 유지한다.
- MY 작업실 러그, 빈 농장 바탕과 배경 불투명도, 농장 오이 표시와 그림자, 설정 권한 행을 조정했다. AR은 원본 프로토타입 반응의 인트로·시작·성공·실패·재도전 시간을 반영했다.

iPhone 17 시뮬레이터의 1206×2622 캡처를 Figma 원본 402×874에 맞춰 측정했다. 작업실 원형 테두리는 Figma (20,740) 104×104px, 시뮬레이터 (21,738) 103×103px였다. 접힌 목록의 선택 정렬 칩은 (20,536) 67×29px 대 (21,537) 66×28px, 펼친 목록은 (20,150) 67×29px 대 (21,151) 66×28px였다. 동일 RGB 근방의 픽셀 경계를 사용했으며, 폰트 래스터 처리·데이터·동적 3D 지도가 달라 전체 화면 픽셀은 동일하지 않다. 녹화에서 정렬 칩 이동은 끝점 1px 부근까지 열기 약 358ms, 닫기 약 363ms였고 전환 설정은 400ms다.

OiFlowChecks 40개, MY·캠퍼스 스크립트, 최종 본 앱/Clip 시뮬레이터 빌드와 AR 화면·번들 글꼴 검사에 통과했다. AR 카메라를 사용하는 실제 성공·타임아웃 전환과 MY 네이티브 화면 이동의 프로토타입 전환 차이는 별도 확인 대상이다.

## 2026-11-04 기존 로컬 작업 통합

`fix/#132-figma-fidelity`의 `783f4fd`에 사용자의 기존 #136 옷장 구현과 미커밋 변경을 통합했다. 원본 checkout의 변경 파일 18개를 해시와 함께 별도 백업했으며 개인 수동 서명 설정은 가져오지 않았다. PR #138에서 되돌린 옷장 구현을 다시 포함하는 것은 이번 사용자의 명시적 통합 요청에 따른다.

- Figma `2876:8316`의 정면 `3294:3164`, 측면 `3616:1540`, 접힌 목록 `2379:4041`, 펼친 목록 `3597:4206`, 요약 `3444:4276`, 상세 `2450:4928`을 다시 비교했다. 최신 6냥이 카드와 포카전 농구 캐릭터 PNG를 원본으로 교체했다. 6냥이 캐릭터 자체는 이미 원본과 동일해 유지했다.
- 실제 3D 지형·건물·좌표·확대/기울기/복귀와 고정 지도 마커 크기를 보존한다. Figma의 배경 이미지나 가상 건수로 실제 지도·서버 데이터를 대체하지 않는다. 메시지/검색/추가, 농부/집, 학교, 원형/방패형 마커, 목록 400ms Ease Out과 백그라운드 갱신 배너 숨김은 #132 구현을 유지한다.
- 기존 옷장 8개 조합과 완성 의상 8종, 색상·데님·사진 레이어, 기기 저장·위치/방위·현장 AR 테스트를 합친다. 학교 버튼을 길게 누르면 `내 오이 현장 테스트`에 진입한다. #132의 지도 헤더에 이전 테스트 버튼을 다시 쌓지 않는다.
- 커스텀 화면의 중복 정의를 제거하고 완료 버튼과 `canContinue/onContinue`를 연결해 이야기 작성·체험에서 카드 단계로 진행할 수 있게 한다. 작성 권한·기기 저장·공개 승인·서버 수집 영수증 경계를 유지한다.
- #133 담당 파일 세 개, 실제 서버/DB, 개인 계정·서명·프로비저닝 설정은 수정하지 않는다. 의상 리소스는 본 앱에만 포함하며 App Clip에 추가하지 않는다.

통합본 검증: 본 앱/Clip Debug 시뮬레이터 빌드 성공, `OiFlowChecks` 40개 통과(56개 production View 렌더 포함), 캠퍼스·MY·서비스·App Clip·정밀 배치·주변 AR·손상 초안 복구 스크립트 통과. 배치 검사는 2,081회 좌표 왕복을 포함한다. 서비스 검사는 옷/색상/데님/사진/위치의 복원·잘못된 저장 거부·교체/삭제를 포함한다. 초기 셸 검사는 Swift 매크로 샌드박스 제한으로 중단되어 권한 있는 실행 환경에서 다시 통과했다.

시뮬레이터에서 실제 지도와 접힌 목록, 옷장 모델 표시를 확인했다. 자동 캡처 중 일부 3D 미리보기는 로딩 중이어서 별도 네이티브 실행으로 확인했다. UI 도구의 탭이 화면 전환으로 전달되지 않아 수동 탭·핀치 왕복 전체는 재검증하지 못했다. 실기기 서명 빌드·야외 GPS/AR·로그인/운영자 승인/다른 기기 동기화는 이번 검증 범위 밖이다. Swift 6 격리 및 기존 API deprecation 경고는 남아 있다.
