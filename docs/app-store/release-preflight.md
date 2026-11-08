# 오이기부 1.0.0 출시 확인 — #221

## 출시 동작과 심사

- 첫 출시는 iPhone 전용이다(#181). 본 앱과 App Clip은 iOS 26.2 이상(#217). 대한민국 무료 배포와 수동 출시를 유지한다.
- 52gibu 운영 DB에서 2026-11-08에 임시 작성 ON과 신고 마이그레이션 `20261106150000` 적용을 읽기 전용으로 확인했다. 공개 이야기는 조회 시점에 0건이었다. 로그인 사용자는 작성 승인 전에도 초안과 사진을 저장하고 공개 검토를 요청한다. 실제 공개는 운영자가 승인한다. 증빙 검토·작성 승인·공식 수납처의 납입 확인은 각각 별개의 절차다.
- 심사 체험: 본 앱 홈 지도 오른쪽 위 **체험하기** → **6냥이오이** → **스토리 보기** → **수집하기** → **시작**. AR 지원 iPhone에서 카메라를 허용하고 30초 안에 오이 3개를 찾은 뒤 **체험 카드 모으기**를 누른다. Clip은 첫 화면 **이야기·AR 체험**에서 같은 화면을 연다. 예시는 로그인·기부·현장 방문 없이 사용할 수 있으며 종료하면 수집 상태가 초기화된다.
- 계정 시험: **MY → 설정**에서 Apple 또는 Google로 로그인하고, 홈 지도 **+ → 오이 만들기**에서 새 이야기를 작성한다. **MY → 설정 → 회원 탈퇴**에서 같은 로그인 제공자로 재인증한다. [Apple 심사 가이드](https://developer.apple.com/app-store/review/guidelines/#before-you-submit)에 따라 팀이 관리하는 일반 사용자 심사용 계정 또는 Apple이 허용한 대체 접근 경로를 준비한다. 심사용 계정에는 운영자 권한·실제 증빙을 넣지 않는다. 로그인 가능 여부를 기기에서 시험한 뒤 자격 증명은 App Store Connect의 비공개 심사 입력란에서만 제공한다.

## App Clip 경험과 실기기 시험

- 기본 URL: `https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip`. 이름은 **오이기부**, 부제목은 **캠퍼스 이야기를 읽고 AR로 오이를 찾아보세요**, 동작은 **열기**. 헤더는 1800×1200의 JPEG 또는 PNG다. 처리된 새 빌드를 선택한 뒤 [기본 경험](https://developer.apple.com/help/app-store-connect/offer-app-clip-experiences/offer-a-default-app-clip-experience)을 등록한다. 기본 링크가 활성화되는 시점과 실제 NFC 시험을 별도로 확인한다.
- [Apple의 로컬 경험 시험](https://developer.apple.com/documentation/appclip/testing-the-launch-experience-of-your-app-clip): 개발 서명 Clip을 iOS 26 iPhone에서 먼저 실행한 후 설정 → 개발자 → 로컬 경험에서 URL과 Clip 번들 ID를 등록한다. 본 앱이 없는 시험 기기에서 NFC 태그·QR을 인식해 카드가 뜨는지, 열기 후 **이야기·AR 체험**을 끝까지 할 수 있는지 확인한다. 전체 앱이 이미 설치된 기기는 동일 URL에서 본 앱으로 들어오는지도 별도로 시험한다. 시험 종료 후 로컬 경험을 제거한다.
- 두 일반 테스트 계정과 기존 권한을 가진 운영자 계정으로 검증한다. 작성자가 가상 제목·사진·위치를 저장하고 검토 요청 → 운영자가 공개 → 다른 계정이 조회·신고·차단 → 운영자가 접수와 처리 상태 확인 → 테스트 계정만 탈퇴한다. 차단 시 본 앱과 Clip 목록에서 숨김·해제를 확인한다. 증빙은 실제 금융·개인 자료 대신 가상 파일을 쓰고 공개 테스트 자료의 정리를 확인한다. 운영 DB 회귀 검사와 사용자가 iPhone에서 로그인해 진행한 검증은 별도로 기록한다.

## 개인정보와 사용 권한

- 스토어의 데이터 공개 항목을 [처리방침](../../README.md#개인정보-처리방침)에 대조한다. 로그인 식별자·이름·이메일, 계정과 연결한 사용 기록, 이야기·사진·신고, 증빙에 들어갈 수 있는 문자·금융 정보, 학적 정보가 해당한다. 팀이 기부금·결제 수단을 직접 받지는 않는다. iPhone 현재 위치로 현장 수집 여부를 기기에서 계산하는 동작과 이야기 배치 좌표 저장을 구분한다. 추적이나 광고를 새로 도입하지 않는다.
- 본 앱은 Paperlogy·Pretendard·Mona12 OFL과 Griun OMIRI 사용 조건을, Clip은 Paperlogy OFL을 번들에 포함한다. `OiSampleGallery01…11`, 예시 카드·본문, 학교 명칭·로고 및 캠퍼스 모델은 팀이 배포 출처와 허용 범위를 확인하고 스토어의 콘텐츠 권한 설문에 반영한다. 기존 예시에는 막걸리 이름과 잔을 든 캐릭터가 있어 연령 설문에서 음주 표현을 반영한다.
- 6장 스크린샷은 최종 앱에서 실제로 제공하는 화면과 대조한다. 예시 화면에는 앱에서 제공하는 ‘체험용’ 표기를 유지한다. 사용자 사진·증빙·개인정보가 보이는 캡처는 사용하지 않는다.

## 아카이브와 스토어 제출

1. `develop`에서 변경을 검증하고 출시 반영 PR로 `main`에 반영한다. 최종 `main`에서 마케팅 버전 1.0.0과 미사용 빌드 번호를 본 앱·Clip에 동일하게 사용한다.
2. Release 아카이브에서 내장 Clip과 iPhone 대상, 최소 iOS 26.2, 본 앱 NFC의 `TAG`( `NDEF` 없음), 개인정보 manifest, 폰트 라이선스를 확인한다. 기기별 Clip 내보내기에 `scripts/check-app-clip-release.py`를 실행해 비압축 15,000,000바이트 미만인지 확인한다. 개발 서명은 iPhone 시험에 쓰고 스토어 배포 서명 및 Organizer **Validate App**은 별도로 확인한다.
3. 두 `Info.plist`에 `ITSAppUsesNonExemptEncryption = false`를 포함한다. iOS `URLSession`의 HTTPS, Keychain, Apple CryptoKit의 SHA-256을 사용하며 iOS 타깃에 별도 암호화 라이브러리를 연결하지 않는다. 이는 암호화를 사용하지 않는다는 뜻이 아니다. 앱이나 의존성의 암호화 범위가 달라지면 [Apple의 수출 규정 안내](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)에 따라 다시 검토한다.
4. 계정 소유자 또는 관리자는 [대한민국 비즈니스 연락처](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-korea-compliance-information)를 확인한다. 스토어 업로드가 승인되면 새 빌드를 선택하고 수출 규정·Clip 경험·심사 접근·콘텐츠 권한·스크린샷을 확인한 뒤 심사 제출한다.
