# Android hi-fi 첫 적용

- 원본: [프로토타입 795:1610](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH/BenchMark?node-id=795-1610)
- 첫 구현: 홈 `1021:4493`, 402×874 기준. Kotlin/Jetpack Compose와 기존 NavHost·LofiModel을 유지한다.
- 브랜치: `feat/#63-android-hifi-home`. 선행 #41은 develop에 병합했다. #43·#45는 이번 작업에 병합하지 않았다.

## 적용과 의도적인 차이

홈 로고·벤치 배너·내 기부 카드·바로가기·현황 영역과 공통 색상을 적용했다. 기존 iOS 에셋의 PNG를 바이트 변경 없이 Android drawable-nodpi로 재사용한다. 벤치 사진은 Figma 원본과 SHA-256이 일치한다. 화면 캡처는 Robolectric 오프스크린 렌더링이며 실제 기기 캡처가 아니다.

- 사용자가 Android 기본 글꼴로 우선 구현하도록 승인했다. Figma의 Griun_OMIRI, [KIM]WILDgag, Pretendard 파일은 저장소에 없으며 타이포그래피가 원본과 다르다. 기본 글꼴의 폭에 맞춰 배너 제목은 19sp로 적용한다.
- iPhone 시스템 바와 SF Symbols는 복제하지 않는다. Android Material 아이콘·탭을 사용하며 기존 홈·나의 기부·벤치·AR 체험 이동을 유지한다. Figma의 후원 탭과 독립 카메라 탭 구성은 후속 화면 구현에 남겨 둔다.
- 고정 루트 크기를 사용하지 않는다. 좌우 20dp를 유지하고 카드 폭은 가용 폭을 사용한다. 배너는 최소 219dp이고 글자 확대·작은 폭에서는 내용에 맞춰 늘어난다. 전체 콘텐츠는 스크롤된다.
- 학교 현황 API가 없으므로 디자인의 17/30·235명·78%를 운영 수치로 표시하지 않는다. 조회 미연결을 명시하며 로컬 기부 예시 내역과 납입 증빙을 구분한다.
- 바로가기는 학교 영수증 책임과 현재 미연결 상태를 설명한다. 실제 영수증 조회·정기후원·이벤트 API를 구현한 것으로 표시하지 않는다.

## 후속 화면

| 영역 | Figma node | 상태 |
| --- | --- | --- |
| 로그인 | 795:1613 | 디자인 조회 완료, 기존 lo-fi 유지 |
| 기부여부 온보딩 | 820:1830 | 후속 적용 |
| 홈 | 1021:4493 | 첫 적용 |
| 내 기부 단일/그리드 | 1173:928 / 1239:1379 | 후속 적용 |
| 후원 시작/설명 | 1450:6836 / 1386:5201 | 디자인 조회 완료, 후속 적용 |
| 후원 단계 | 1386:5314 / 1399:5544 / 1423:6019 / 1423:6240 / 1450:6556 / 1450:6769 | 학교 공식 기부 절차와 대조 필요 |
| 지도·프로필·알림 | 1308:3217 / 1308:3211 / 1308:3214 | 원본 상세 내용이 비어 있음, 기존 흐름 유지 |
| Apple Wallet | 1308:2333 | Android 구현 범위와 제품 정책 미확정 |

Needs confirmation: 전체 hi-fi 완료, 실제 지도·학교 데이터·학교 납입 확인 연동, 실제 Android 기기 및 접근성 서비스 확인은 후속 작업이다. Apple Wallet은 Android에서 동일 API로 구현할 수 없으며 별도 제품 결정이 필요하다.

## 검증

```bash
cd apps/android
JAVA_HOME='/Users/don/Library/Java/JavaVirtualMachines/ms-21.0.7/Contents/Home' ANDROID_HOME='/Users/don/Library/Android/sdk' ./gradlew --no-daemon assembleDebug testDebugUnitTest lintDebug
```

기존 이동 테스트 6개와 hi-fi 테스트 4개로 홈 진입, 미연결 수치, 학교 영수증 안내, 프로필·기부 시작·내 기부 이동, 320/402/600dp 화면을 검증한다.
