# 오이기부 Icon Composer 원본

`OiDonation.icon`을 Icon Composer로 열어 편집합니다. 2026-10-26에 기존 앱의 투명 로고 `apps/ios/OiDonation/Assets.xcassets/OiLogo.imageset/OiLogo.png`를 가져와 만들었습니다.

- 배경: 사용자가 수정한 크림색–연두색 세로 그라디언트. 로고와 독립적으로 색상을 변경할 수 있습니다.
- 전경: 원본 PNG 로고 한 레이어. 배율 65%, 중앙 배치로 기존 앱 아이콘의 크기와 여백을 맞췄습니다.
- Liquid Glass: Icon Composer의 그룹 효과를 사용합니다. 밝은 모드와 어두운 모드 미리보기를 확인했습니다.
- 하트·오이·무늬는 원본 PNG 안에 합쳐져 있습니다. 개별 도형 편집용 벡터 레이어는 아닙니다.
- 파일 안에 이미지가 포함되므로 원본 경로에 의존하지 않습니다.

2026-10-26부터 전체 앱 `OiDonation` 타깃의 Debug·Release 아이콘으로 연결했습니다. Xcode 프로젝트가 이 파일을 상대 경로로 직접 참조하며 `ASSETCATALOG_COMPILER_APPICON_NAME = OiDonation`으로 컴파일합니다. Icon Composer에서 이 파일을 저장한 뒤 앱을 다시 빌드하면 수정 내용이 반영됩니다. 복사본을 따로 갱신할 필요는 없습니다.

기존 `AppIcon.appiconset`은 원본 보존용으로 남아 있고 전체 앱의 기본 아이콘으로 선택되지는 않습니다. App Clip은 기존 AppIcon 설정을 유지합니다. 개인 서명·Bundle ID·프로비저닝 설정은 변경하지 않았습니다.

참고: [Apple — Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
