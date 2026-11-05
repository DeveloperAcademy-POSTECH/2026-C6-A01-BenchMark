# 정식 배포의 필수 API 사유 선언

2026-11-06 / #164. 본 앱과 App Clip은 각 타깃 루트의 `PrivacyInfo.xcprivacy`를 번들 리소스로 포함한다. Xcode의 파일 시스템 동기화 그룹이 각 파일을 해당 타깃에 포함하며, 공유 Swift 소스 예외 목록에는 manifest를 추가하지 않는다.

| 대상 | API와 사용 목적 | 선언 사유 |
| --- | --- | --- |
| 본 앱 | `UserDefaults.standard`: 자체 농장·외형 설정 | `CA92.1` |
| 본 앱·App Clip | `UserDefaults(suiteName:)`: 동일 앱 그룹의 카드 수집 기록 | `1C8F.1` |
| 본 앱·App Clip | `ProcessInfo.systemUptime`: AR 게임의 30초 경과 시간 계산 | `35F9.1` |

경과 시간 API는 게임 타이머에서만 사용하며 시스템 부팅 시각을 서버에 전송하지 않는다. 다른 앱의 설정·기기 지문·광고 추적을 위한 사용 사유는 선언하지 않는다. 실제 호출부는 `StoryCollectionStore`, `MYFarmerAppearanceStore`, `CampusStoryStore`, 공유 `ARGameViewModel`이다.

이 파일은 필수 사유 API 사용을 선언한다. App Store Connect의 개인정보 수집 항목 신고나 공개 개인정보처리방침 URL을 대신하지 않으며, 수집하지 않는 앱이라고 선언하는 빈 데이터 수집 배열을 추가하지 않는다.

확인할 때는 `plutil -lint`로 두 파일을 검사한 뒤 Release 아카이브의 `OiDonation.app/PrivacyInfo.xcprivacy`와 `OiDonation.app/AppClips/OiDonationClip.app/PrivacyInfo.xcprivacy`를 각각 확인한다. 서명 전 아카이브 성공은 배포 서명·업로드·Apple 심사 통과를 의미하지 않는다.

기준: [Apple 필수 사유 API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [TN3183 manifest 형식](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
