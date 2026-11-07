# 체험 지도·이야기와 AR 수집 윤곽 — #214

## 적용 범위

2026-11-07 사용자 요청. 본 앱 지도와 App Clip의 기존 체험하기 진입에서 같은 오프라인 탐색 화면을 연다.

| Figma 노드 | 구현 |
|---|---|
| `2379:4041` | 예시 지도, 선택 가능한 이야기 마커, 접힌 목록 |
| `3597:4206` | 목록 펼치기/접기, 최신순·오래된순 정렬 |
| `3444:4276` | 오이 요약, 이야기 상세 진입, 카드 확대, AR 체험 |
| `2450:4928` | 기부자 소개·이야기·오이/카드·11장 갤러리·위치·관련 예시 |
| `3180:4501` | 곰인형을 든 고양이: AR 카메라·수집 슬롯의 동일 이미지/정규화 비율 |

[Figma](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2379-4041&m=dev)

## 기존 정책과 디자인 적용

- 기존 `CampusStoryExamples`의 서로 다른 예시 3개와 `CampusStyle`의 글꼴·태그·목록 행을 재사용한다. Figma 목록에 반복되는 항목으로 가짜 이야기 10개를 만들지 않는다.
- 체험용임을 계속 표시하고 실제 기부 횟수·학교 확인·계정 도감 저장을 만들지 않는다. ‘이어서 기부하기’는 체험에서 실제 기부가 연결되지 않는다는 안내를 보여 준다.
- AR 체험은 기존 6냥이 이야기와 30초/3마리 게임이다. 다른 예시에서는 버튼에 ‘6냥이 AR 체험’을 명시한다. 수집은 `OiSampleExperienceView`의 메모리 상태이며 체험 종료 시 초기화한다.
- 지도는 Figma 원본 배경과 선택 가능한 마커를 합친 오프라인 예시다. GPS·원격 공개 이야기·대용량 캠퍼스 3D 모델을 App Clip에 추가하지 않는다.
- 기존 출시 결정대로 Paperlogy를 사용한다. PearToucan·와일드각 폰트를 재도입하지 않는다.

## 이미지 및 AR 구현

- Figma 도구의 임시 URL에서 원본을 내려받았으며 URL을 런타임에서 사용하지 않는다.
- 고양이 `561d5.png`와 기존 `OiStoryCardCats/cats.png`의 SHA-256은 동일하다: `25aa42a379aa29a1f0235bb7af5311eec8b07a9e870e1900c0f05f4e85f17aa1`.
- 기존 오이·카드·농부·위치 이미지 6개는 이름과 바이트를 유지하며 두 타깃용 `OiSampleAssets.xcassets`로 옮겼다. 전체 앱 에셋 카탈로그를 Clip에 포함하지 않는다.
- 갤러리 11장은 원본 비율 그대로 최대 1280px JPEG(품질 82), 배경은 최대 1600px, 지도 장식 캐릭터는 최대 300px PNG로 준비한다. 원본 갤러리는 기존 본 앱 경로에 보존한다.
- 고정된 우주복 모양 `ARGameCollectionTray` 대신 동일한 정규화 이미지의 알파에서 빈 슬롯 윤곽을 계산한다. AR 시작 시 한 번 해석한 `UIImage`를 카메라 텍스처와 HUD에 함께 넘겨 원격 이미지 실패/대체 이미지 상황에서도 서로 다른 캐릭터가 되지 않게 한다.
- 수집 전·후 모두 72×118 슬롯에 동일 비율로 맞춘다. 캐릭터 원본이나 이미지를 새로 그리지 않는다.

## 검증

- 본 앱과 내장 App Clip의 Debug 테스트 빌드 및 Release Simulator 빌드 성공. 팀/프로파일/서명 설정은 변경하지 않았다.
- `OiFigmaFidelityVisualTests/testSampleExperienceCaptures`, `testSampleARArtworkAndCollectionOutline` 통과. 375×667 / 402×874 / 440×956 / 최대 Dynamic Type에서 지도·목록·요약·상세·수집 결과 24장, AR 슬롯 0/1/3개 상태 3장으로 총 27개 캡처를 확인했다. 최종 내비게이션 안내/접근성 수정 후 화면 캡처 검사를 다시 통과했다.
- Device Hub의 iPhone 18 Pro / iOS 27.2에서 본 앱의 체험 버튼 → 지도 → 목록 펼치기·오래된순 정렬 → 6냥이 요약 → 상세 → 갤러리 확대/닫기 → AR 시작 → 미지원 안내/복귀를 직접 조작했다. 실제 기부 연결 방지 안내도 확인했다.
- 체험 고지를 내비게이션 상단의 ‘체험용’ 버튼으로 표시하여 하단 수집 버튼을 가리지 않는다. 큰 글자 모드는 지도 위에 목록을 펼치고 정렬 메뉴를 세로로 배치한다.
- `run-app-clip-checks.sh`, `run-campus-checks.sh`, `run-architecture-checks.sh`, `run-ar-recovery-checks.sh`, `run-ar-camera-lifecycle-checks.sh` 통과.
- 실제 Debug/Release Clip 번들에서 이미지 27개·Paperlogy OFL 포함과 Paperlogy 6개 굵기의 등록/구분을 확인했다.
- `plutil -lint`와 `git diff --check` 통과. 공유 위치로 옮긴 기존 이미지 6개와 메타데이터는 원래 바이트와 동일하다.

실기기 카메라로 움직이며 3마리를 수집하는 AR 과정과 실기기 App Clip 실행, Apple 배포 검증은 이번에 실행하지 않았다. Simulator의 AR 미지원 안내까지 확인했으며 서명 없는 Simulator의 계정 키체인 오류는 계정 기능 검증에 사용하지 않았다. App Store 업로드나 develop/main 병합은 하지 않는다.

대표 캡처: [지도](sample-214/sample-map-402x874.png), [목록](sample-214/sample-list-402x874.png), [요약](sample-214/sample-summary-402x874.png), [상세](sample-214/sample-detail-402x874.png), [AR 윤곽과 수집](sample-214/sample-ar-slots-1-402x874.png).
