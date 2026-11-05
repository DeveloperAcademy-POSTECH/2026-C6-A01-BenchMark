# 사진 테스트 — 2026-10-21 / #87

홈 최하단 `사진 테스트` → `콜라주` 또는 `레이아웃`으로 이동한다.

- **콜라주**: 시스템 사진 선택기에서 1~4장을 순서대로 선택한다. 사진 비율과 순서를 유지하고 가로·세로 결합을 비교하여 빈 공간 없는 직사각형을 만든다. 자르거나 늘리지 않으며 전체 결과 비율은 선택한 사진에 따라 달라진다.
- **레이아웃**: 세로 2칸·가로 2칸·세로 3칸·가로 3칸·큰 사진+2칸·4칸 중 선택한다. 캔버스는 9:16·4:5·1:1 중 고른다. 빈 칸을 누르면 사진을 선택하고, 채운 칸을 누르면 해당 칸을 선택한다. 선택한 칸의 교체·제거·드래그·확대와 위치 슬라이더·구도 초기화를 제공한다. 틀을 채우도록 비율을 유지하여 자른다. 틀·캔버스 변경 시 구도를 초기화하며 숨겨진 칸의 사진은 유지한다.
- **완성 이미지**: 모든 칸에 사진이 있어야 실행할 수 있다. 결과 미리보기에서 사진 보관함 저장 또는 시스템 공유를 제공한다. 사진 보관함에는 사용자가 저장을 누를 때만 추가 권한을 요청한다. 거절·저장 실패는 안내하고 공유를 계속 사용할 수 있다.

사진은 서버로 전송하지 않는다. 사진 선택은 전체 보관함 읽기 권한을 요청하지 않는 시스템 PhotosPicker를 사용한다. 로딩은 순차 수행하고 ImageIO로 회전 정보를 반영해 긴 변 2,048px까지 축소한다. 결과 이미지의 긴 변도 최대 2,048px이며 원본 해상도 보존을 보장하지 않는다. 선택 취소 시 기존 편집 내용을 유지한다. 로딩 실패 시 이전 사진을 보존하고 다시 불러오기를 제공한다. 편집은 메모리 안에만 유지되므로 편집기를 나가거나 앱이 종료되면 사라진다.

## 검증

Xcode 27.0, 앱 배포 대상 iOS 26.2, 기존 Swift 언어 모드 5를 유지했다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/OiDonation.xcodeproj -scheme OiDonation -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/benchmark-photo-test-87-build CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-collage-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-architecture-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-ar-video-checks.sh
```

모듈 캐시 쓰기가 제한된 환경에서는 `CLANG_MODULE_CACHE_PATH`와 `SWIFT_MODULECACHE_PATH`를 쓰기 가능한 임시 경로로 지정한다.

이미지 검증은 별도로 준비한 작업 전용 시뮬레이터에서 실행한다. 아래 스크립트는 시뮬레이터를 생성·부팅·종료하지 않는다. 지정한 시뮬레이터에 동일한 테스트 앱이 있으면 중단하고, 이번 실행에서 설치한 테스트 앱과 임시 컴파일 폴더만 정리한다. 결과 폴더는 새 절대 경로를 사용한다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-collage-image-checks.sh <booted-simulator-udid> <new-absolute-output-directory>
```

- 기하 검증: 7,380개 비율 조합의 원본 비율·경계·겹침·전체 면적, 모든 틀, 크롭 한계, 미리보기와 내보내기의 좌표 일치.
- 이미지 검증: 1~4장 자동 결과, 6개 틀의 합성, 빈 칸·손상 데이터 실패, EXIF 회전, 큰 이미지 축소.
- UI: 격리된 UIKit 테스트 앱이 실제 SwiftUI 메뉴·편집기·캔버스를 작은/기준/큰 너비 및 큰 글자 설정에서 렌더링한다. 앱 실행 화면의 터치 자동화 검증과는 구분한다.
- Needs confirmation: 실기기의 사진 선택기·iCloud 다운로드·핀치/드래그 동작, 사진 저장 허용·거절, 시스템 공유의 전체 사용자 흐름은 수동 검증하지 않았다.
