# MY 전체·농부 꾸미기 — #158

2026-11-05 Figma MY 전체 후속 요청과 사용자 답변을 반영한다. 기존 [설정·학교 인증 기록](settings-view-158.md)과 같은 PR에서 진행한다.

## 확인한 디자인

[Figma 프로토타입 ver.2](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2339-2109)의 MY 섹션 `2876:8320` 전체 19개 화면과 아이템 선택 프레임 8개를 대조했다.

| 영역 | 노드 | 반영 |
| --- | --- | --- |
| 작업실 | `2744:1732`, `4352:13519` | 로그인 전 안내·설정 로그인 진입·나가기, 로그인 후 농장 이름·실제 농부 의상 |
| 내 농장 | `2744:1731`, `2876:7298` | 실제 소유 이야기·독립 농장 이름, 기존 승인 정책 유지 |
| 도감 | `2510:5695`, `4240:11327`, `2558:9881`, `4240:11357`, `2558:10110` | 카드 격자·학교 폴더·빈 상태·헤더·비활성 MY 버튼 |
| 확대 카드 | `2558:10332` | 362×502 카드와 하단 상세/핀, 닫기 터치 영역 |
| 설정·학교 인증 | `2835:2654`, `4340:13157`, 학교 5단계 | 기존 구현과 공개 검색 편집 진입 유지 |
| 농부 꾸미기 | `3188:1411`, 선택 프레임 8개 | 캐릭터별 상·하의·신발·세트·악세서리, 저장·되돌리기 |
| 피클코인 | `3892:1850` | 사용자 결정대로 비활성, 구매·광고·보상 미연결 |

402×874pt 기준은 상태바 62pt와 홈 인디케이터 34pt를 포함한다. 시스템 바를 이미지로 그리지 않는다. 작업실은 가로폭에 맞춰 장면을 배치하고 짧은 화면에서는 세로 스크롤한다. 다른 화면도 375×667·402×874·440×956 및 최대 Dynamic Type을 확인한다. 큰 글자에서는 꾸미기 저장/되돌리기와 착용 설명을 세로 배치하고 도감 정렬도 콘텐츠와 함께 스크롤한다.

## 원본과 착용 계약

선택지 그림은 프로토타입 ver.2, 실제 착용과 몸체는 [큐컴버 옷장](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=4279-290)을 사용한다. 사용자 확인대로 위쪽 선택 프레임은 큐, 아래쪽은 컴버다. 새 몸체 `4511:2334`·`4511:2333`도 실제 원본을 확인했다.

- 120개 설계 상품 중 큐 63개·컴버 54개, 총 117개를 해당 캐릭터에서 제공한다.
- 큐 꿀벌 머리띠·컴버 학생증·컴버 청멜빵은 해당 몸체용 착용 레이어가 없으므로 그 캐릭터의 선택지에서 제외한다. 사용자 결정대로 가능한 캐릭터에게만 연다.
- 포즈·모자·스페셜은 소스가 없어 비활성으로 표시한다. ‘세트 선택 프레임’이라는 이름의 프레임은 실제 내용이 악세서리여서 그 내용대로 분류한다. 세트는 하의 프레임 맨 아래의 두 의상이며 컴버 청멜빵 제외 후 컴버에는 한 벌을 제공한다.
- 원본 167개를 SHA1=Figma imageHash로 검사했다. 선택지와 착용의 그림이 다른 경우에도 서로 바꾸지 않는다. 원본 파일 합계 약 106.5MiB이며 앱 번들에만 포함한다. App Clip에는 추가하지 않는다.
- JSON에는 원본 해시·선택지/착용 노드·실측 affine·CROP·clip을 남긴다. 임시 다운로드 URL, 기기 경로, 실제 사용자 자료는 넣지 않는다.
- 몸체→신발→하의→상의/세트→악세서리 순서다. 신발의 좌/우 clipping과 액세서리 회전을 유지하고 가격 글자는 착용 레이어에서 제외한다. 세트는 상·하의를 교체하며 신발·악세서리는 함께 고를 수 있다.
- 컴버 검정 반팔·공룡 상의 두 썸네일이 원본 디자인에서 마스크 밖에 밀려 있었다. 같은 원본의 정상 셀 좌표로 바로잡았다.

## 사용자 결정과 서버 경계

전부 무료이며 코인·광고 보상·기부 최소금액을 새로 적용하지 않는다. Figma의 ‘5,000원 이상·인증 후 코인 지급’은 미확정 문구로만 보관한다. MY 필터, 본인인증, 회원 탈퇴는 비활성 버튼이다. 작업실·홈의 본인 이름은 공개 `farm_name`을 표시한다.

`20261105101848_oi_farmer_outfit.sql`은 계정 본인 전용 private 의상 테이블과 읽기/저장 RPC를 추가한다. 캐릭터·버전·6개 부위의 제한된 ID만 저장한다. 대표 계정·현재 세션과 반환 소유자를 확인하고 이전 계정의 늦은 응답을 무시한다. 대표 계정 의상을 통합 후에도 유지한다. 저장 중 닫기를 막고 요청은 화면 수명에 연결하며, 실패 시 편집을 유지한다. 늦게 도착한 서버 값은 편집 중인 선택을 바꾸지 않고 되돌리기 기준만 갱신한다.

기존 기기의 classic/casual 표시는 서버 의상이 없는 동안 유지한다. 사용자가 저장해야 서버 값이 된다. 새 capability가 없는 서버는 저장 성공을 가장하지 않고 준비 안내를 표시한다. 원격 migration·배포·실계정 다중 기기 시험은 수행하지 않았다.

최신 develop의 공개 기부자 검색 정보 편집은 보존한다. 공개 이름·학과·입학연도와 학교 인증의 private 학과·입학년도는 서로 다른 값이며, 인증 자료를 검색 정보로 복사하지 않는다.

## 검증 기록

최신 develop `d460e25` 통합 뒤 iOS 빌드·65개 테스트·105회 렌더를 통과했고 101개 PNG를 확보했다. 10개 비교 이미지에서 117개 의상의 선택지와 실제 착용을 나란히 확인했다. 기준/작은/큰 화면·접근성 및 작은 화면+최대 글자 크기, 6자 농장 이름을 확인했다. Node 56개와 격리 PostgreSQL의 소유권·계정 통합·입력 검증도 통과했다. 공개/비공개 학적정보 분리와 편집 비간섭, 저장 실패·소유자 불일치·계정 변경의 늦은 응답, 공개 정보만 저장한 계정의 통합 확인까지 검증했다. 새 통합 판정 SQL 검사는 동일 계정 요청 누적으로 제한에 걸린 첫 실행 뒤 SAVEPOINT로 각 사례를 격리해 통과했다. 운영 요청 제한은 변경하지 않았다.

시각 캡처는 실제 production View를 가상 계정과 원본 에셋으로 렌더한다. 매번 UIWindow를 key window로 만들지 않으며, 숨김 창까지 scene에서 분리됐고 기존 창 상태가 유지됐는지 단언한다. 별도 앱 창·Computer Use 세션은 열지 않았다. 최대 동시 실행 그룹은 3개(전용 시뮬레이터·테스트 실행기·한 개의 순차 캡처 창)이며 사용하지 않는 시뮬레이터는 매 검증 직후 종료·삭제한다.

실행 환경은 설치된 Xcode 27.1, 앱 iOS 26.2·Swift 언어 모드 5를 유지했다. 테스트 대상은 iOS 27.0 전용 시뮬레이터였다. 기존 Swift 5 동시성 경고·AppIntents 메타데이터·헤드리스 RealityKit/SDK 진단은 남아 있으며, 실제 AR·카메라·로그인·다중 실기기 검증으로 간주하지 않는다.

학교 상세 빈 상태는 기존 도감의 그림을 재사용하고 갈색 배경에서는 검정 글씨로 대비를 확보한다. 최대 글자 크기에서는 그림을 96×150으로 줄여 문장을 스크롤할 수 있게 한다. 꾸미기의 닫기 버튼은 저장하지 않고 나가는 경로를 제공하며, 활성화하지 않은 코인 컨트롤은 표시하지 않는다.

### 실행한 명령

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiFlowChecks -configuration Debug -destination 'platform=iOS Simulator,id=E86BF684-C3DB-484B-AE67-B8B5818A34E4' -derivedDataPath /private/tmp/benchmark-settings-158-build -resultBundlePath /private/tmp/benchmark-my-158-integrated.xcresult CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -only-testing:OiDonationTests/OiRemoteStoreTests -only-testing:OiDonationTests/OiSchoolEvidenceContractTests -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testEmptyCollectionCaptures -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testFarmerAppearancePersistsForItsOwnerOnly -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testFarmerWearableAndThumbnailContactSheets -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testFarmerWardrobeAssetsAndSelectionContract -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testMYScreenCapturesWithoutRemoteStore -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testMYCollectionCaptures -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testMYSettingsCapturesWithOfflineAccounts -only-testing:OiDonationTests/OiFigmaFidelityVisualTests/testFarmCapturesWithOfflineOwnedStory test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/benchmark-settings-158-module-cache SWIFT_MODULECACHE_PATH=/private/tmp/benchmark-settings-158-module-cache sh apps/ios/Tests/run-my-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/benchmark-settings-158-module-cache SWIFT_MODULECACHE_PATH=/private/tmp/benchmark-settings-158-module-cache sh apps/ios/Tests/run-oi-service-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/benchmark-settings-158-module-cache SWIFT_MODULECACHE_PATH=/private/tmp/benchmark-settings-158-module-cache sh apps/ios/Tests/run-campus-checks.sh
python3 supabase/tests/run-account-merge-db-checks.py
(cd supabase && npm test)
git diff --check
```

마지막 VoiceOver 착용 요약 보완 뒤 아래 빌드도 exit 0으로 통과했다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiDonation -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/benchmark-settings-158-build CODE_SIGNING_ALLOWED=NO build
```

### 화면

- [my-workshop-402x874](assets/my-158/my-workshop-402x874.png)
- [my-workshop-signed-in-402x874](assets/my-158/my-workshop-signed-in-402x874.png)
- [my-workshop-signed-in-375x667](assets/my-158/my-workshop-signed-in-375x667.png)
- [my-workshop-signed-in-440x956](assets/my-158/my-workshop-signed-in-440x956.png)
- [my-farmer-signed-in-402x874](assets/my-158/my-farmer-signed-in-402x874.png)
- [my-farmer-signed-in-accessibility5](assets/my-158/my-farmer-signed-in-accessibility5.png)
- [my-collection-all-content-402x874](assets/my-158/my-collection-all-content-402x874.png)
- [my-collection-schools-content-402x874](assets/my-158/my-collection-schools-content-402x874.png)
- [my-collection-schools-empty-402x874](assets/my-158/my-collection-schools-empty-402x874.png)
- [my-collection-school-content-small-accessibility5](assets/my-158/my-collection-school-content-small-accessibility5.png)
- [my-collection-schools-empty-accessibility5](assets/my-158/my-collection-schools-empty-accessibility5.png)
- [my-settings-signed-in-402x874](assets/my-158/my-settings-signed-in-402x874.png)
- [farmer-kyu-accessory-contact](assets/my-158/farmer-kyu-accessory-contact.png)
- [farmer-kyu-set-contact](assets/my-158/farmer-kyu-set-contact.png)
- [farmer-cumber-top-contact](assets/my-158/farmer-cumber-top-contact.png)
- [farmer-cumber-accessory-contact](assets/my-158/farmer-cumber-accessory-contact.png)
- [farmer-kyu-bottom-contact](assets/my-158/farmer-kyu-bottom-contact.png)
- [farmer-kyu-shoes-contact](assets/my-158/farmer-kyu-shoes-contact.png)
- [farmer-cumber-bottom-contact](assets/my-158/farmer-cumber-bottom-contact.png)
- [farmer-cumber-set-contact](assets/my-158/farmer-cumber-set-contact.png)
- [farmer-cumber-shoes-contact](assets/my-158/farmer-cumber-shoes-contact.png)
- [farmer-kyu-top-contact](assets/my-158/farmer-kyu-top-contact.png)

창 정리 단언 105회와 시뮬레이터 삭제를 통과했다. 이 검증에서 사용한 시뮬레이터 `E86BF684-C3DB-484B-AE67-B8B5818A34E4` 및 앞선 두 전용 시뮬레이터는 모두 종료·삭제했다. 임시 PostgreSQL은 성공·실패 모두 PID 파일·소켓 제거를 검사했고, 실패 DB의 가상 자료도 정리했다. 사용자 원본 체크아웃의 개인 서명 변경은 보존했다.
