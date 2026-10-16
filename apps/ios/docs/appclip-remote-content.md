# NFC App Clip 원격 이야기·AR 촬영 — #79

구현일: 2026-10-16. `feat/#79-appclip-remote-ar`은 미병합 #69의 기본 타깃(`fe94802`)을 기반으로 최신 develop(`4e31872`)을 병합한 후속 브랜치다. #69의 원격 브랜치나 다른 팀원 파일은 수정하지 않았다. #73 명패 미리보기는 이 브랜치에 포함하지 않는다.

## 동작

1. NFC NDEF URI에 `https://<공개 도메인>/benches/<벤치ID>`를 기록한다.
2. App Clip은 호출 URL을 검증하고 `GET <API_BASE>/v1/benches/<ID>/story`로 공개 이야기를 가져온다. `/stories/<ID>`는 `GET <API_BASE>/v1/stories/<ID>`를 사용한다.
3. 사진만 먼저 내려받아 이야기를 표시한다. 원본은 8MB 이하, 디코딩은 최대 1600px 썸네일이다.
4. AR 버튼을 누르면 카메라 권한과 지원 기기를 확인하고 해당 USDZ 한 개를 다운로드한다. 80MB 제한·진행 표시·SHA-256 검증 후 RealityKit에서 연다.
5. 바닥 탭으로 배치하고 핀치/두 손가락 회전으로 조절한다. 자동 환경 조명으로 렌더링하고 ARView snapshot을 미리보기·시스템 공유에 전달한다. 사진과 영상은 서버로 전송하지 않는다. 직접 PhotoKit 저장·영상·경기장 합성·캐릭터 목록은 Clip에 포함하지 않는다.
6. 전체 앱이 설치된 경우 동일한 URL을 같은 콘텐츠 화면으로 연결한다. 전체 앱과 Clip은 네트워크·이야기·AR 소스를 공유하지만 Clip에는 전체 앱 에셋과 USDZ를 포함하지 않는다.

## 운영 설정 — 아직 미확정

Xcode Build Settings 또는 별도 개발용 xcconfig에서 **두 타깃 모두** 다음 값을 제공한다. 기존 개인 DEVELOPMENT_TEAM은 유지한다. 비밀키는 필요 없으며 서비스 역할 키를 앱에 넣지 않는다.

| 설정 | 예시(운영 주소 아님) |
| --- | --- |
| OI_CLIP_PUBLIC_HOST | clip.example.org |
| OI_CLIP_API_BASE_URL | https://api.example.org |
| OI_CLIP_ASSET_HOSTS | cdn.example.org,api.example.org |

기본 `unconfigured.invalid`와 빈 API 값은 연결 준비 안내를 표시한다. 실제 NFC 서비스가 설정된 것처럼 동작하지 않는다. Redirect는 전부 거부하므로 CDN 최종 파일 주소를 사용한다. HTTPS/기본 443, 설정 호스트만 허용한다. 호출 URL은 query·fragment·인증정보·추가 경로·비표준 포트를 허용하지 않는다.

DEBUG에서만 같은 이름의 환경 변수로 설정을 덮어쓸 수 있다. `OI_CLIP_TEST_URL`은 Xcode 개발용 실행 URL이며 운영에서는 무시한다. `OI_CLIP_ALLOW_LOCALHOST=1`은 DEBUG의 localhost/127.0.0.1 HTTP 테스트에만 허용한다. Release에서는 HTTP가 거부된다.

## 제안 API 계약

다음 형식은 **App Clip용 새 계약**이다. 기존 POSTECH/팀 서버가 이미 제공하는 응답이라고 가정하지 않는다. `404`는 이야기 없음/비공개로 사용하고, 서버에서도 공개 여부를 검사한다.

```json
{
  "id": "story-001",
  "benchID": "bench-001",
  "published": true,
  "title": "다시 만날 우리에게",
  "body": "공개에 동의한 이야기 본문",
  "donorDisplayName": "공개 동의한 이름 또는 익명",
  "images": [{"url": "https://cdn.example.org/stories/001-v1.jpg"}],
  "character": {
    "name": "넙죽이",
    "heightMeters": 1.0,
    "asset": {
      "url": "https://cdn.example.org/models/neopjuk-v1.usdz",
      "sha256": "파일의 SHA-256 소문자 64자리 hex 값"
    }
  }
}
```

`character`는 null, `images`는 빈 배열일 수 있다. 이미지는 최대 12개, API JSON 512KB, 본문 2만 자로 제한한다. 모델 URL은 `.usdz`여야 하며 실제 파일 해시를 필수 제공한다. URL·해시로 구분해 최대 약 160MB/24시간의 임시 캐시를 청소한다. OS가 Clip 캐시를 삭제할 수 있으므로 영구 저장을 가정하지 않는다. 모델의 다운로드 크기 제한이 압축 해제 후 메모리 사용량을 보장하지 않으므로 신뢰할 수 있는 운영자가 검수한 독립형 USDZ만 배포하고 텍스처·메시를 경량화한다.

## GitHub 서버 조사 결과

- 기존 웹은 `apps/web/src/app/api/stories/[id]/photo/route.ts`에서 돗자리 이야기 사진을 제공한다. 공개·납입 확인 또는 관리자 조건을 검사한다. 그 공개 이미지 URL을 콘텐츠에 사용할 수 있으나 실제 공개 상태와 주소는 운영자가 확인해야 한다.
- 현재 공개 이야기 페이지는 웹 서버 렌더링이며 벤치→스토리→모델 메타데이터 API는 발견하지 못했다.
- Android의 Supabase 주소는 인증 연결 근거이며 스토리/모델 저장소가 이미 있다는 근거는 아니다.
- 새 API 경로는 서버 담당자와 합의 후 어댑터를 수정하거나 실제 서버에 구현한다. 기존 웹의 비공개 사진 접근 조건을 우회하지 않는다.

## 로컬 검증

저장소 루트에서:

```sh
python3 apps/ios/Tests/Fixtures/clip-content-server.py \
  --model apps/ios/OiDonation/Resources/Characters/neopjuk.usdz \
  --image apps/ios/OiDonation/Assets.xcassets/HomeBench.imageset/HomeBench.png
sh apps/ios/Tests/run-appclip-content-checks.sh
```

개발용 로컬 서버를 실행한 뒤 Xcode에서 **`OiDonationClipLocal`** 스킴을 선택하면 다음 Run 환경 변수가 자동 적용된다. 일반 `OiDonationClip` 스킴은 운영 설정 주입용이며 이 테스트 값을 포함하지 않는다.

```text
OI_CLIP_PUBLIC_HOST=clip.test
OI_CLIP_API_BASE_URL=http://127.0.0.1:8765
OI_CLIP_ASSET_HOSTS=127.0.0.1
OI_CLIP_ALLOW_LOCALHOST=1
OI_CLIP_TEST_URL=https://clip.test/benches/demo-bench
```

`127.0.0.1`은 Mac/iOS Simulator 테스트용이다. 실제 iPhone은 이 주소로 Mac에 연결할 수 없으므로 승인된 HTTPS 개발 서버를 사용한다. 테스트 서버는 loopback에만 바인딩하고 개발용 예시만 제공한다. 실제 NFC는 시뮬레이터로 검증할 수 없다.

## 배포 및 용량

NFC 실행은 15MB를 기준으로 한다. `check-appclip-size.py <Release-iphoneos/OiDonationClip.app>`는 번들의 파일 크기 합과 USDZ 제외를 검사한다. 최종 판정은 서명된 Archive를 export한 App Thinning Size Report/ App Store Connect 결과로 확인한다. Debug Simulator 용량을 배포 용량으로 사용하지 않는다.

1. 학교/팀이 소유한 HTTPS 도메인과 API·CDN 확정.
2. 같은 개발팀에 전체 앱/Clip ID 등록 및 Associated Domains·App Clip 프로비저닝 설정.
3. 도메인 `/.well-known/apple-app-site-association`에 다음 구성. `TEAMID`는 실제 Apple 팀 ID이며 개인 계정 간 임의 공유하지 않는다.

```json
{
  "appclips": {"apps": ["TEAMID.com.Spero.OiDonation.Clip"]},
  "applinks": {"details": [{"appIDs": ["TEAMID.com.Spero.OiDonation"],
    "components": [{"/": "/benches/*"}, {"/": "/stories/*"}]}]}
}
```

4. App Store Connect에서 Advanced App Clip Experience와 NFC 호출 URL을 연결하고 카드 이미지·문구를 등록. 이 카드는 iOS 시스템이 표시하며 앱 화면으로 흉내 내지 않는다.
5. 실제 NFC 태그에 URI 기록 후 Local Experiences/TestFlight/검토된 배포로 확인.

운영 API·CDN·AASA·App Store Connect 등록·실제 NFC 및 실제 iPhone AR 촬영 검증은 외부 설정이 필요하며 코드만으로 완료했다고 보지 않는다. 네트워크 불량·빈 이야기·카메라 거부·추적 손실·모델 로드 실패·닫기/재진입·공유 취소를 현장에서 추가 검증한다.

## 공식 문서

- https://developer.apple.com/documentation/appclip/creating-an-app-clip-with-xcode
- https://developer.apple.com/documentation/appclip/associating-your-app-clip-with-your-website
- https://developer.apple.com/documentation/appclip/interacting-with-app-clip-codes-in-ar
- https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes/

## 이번 검증 결과

- 네트워크 통합 테스트: 호출 URL·공개 여부/ID 대응·이미지/실제 USDZ 다운로드·SHA/캐시·용량·외부 호스트/redirect 거부·취소 통과.
- 기존 아키텍처 검증 통과. 전체 앱+Clip Simulator Debug 빌드 통과.
- 실제 기기용 비서명 Clip Release 빌드 통과. 번들 파일 합 **743,623 bytes (약 0.74MB)**, 내장 3D 파일 없음. 서명/스토어 thinning 결과가 아님.
- iPhone 17 Pro iOS 26.5 Simulator에서 개발용 벤치 URL → 실제 HTTP API → 사진·이야기 표시, AR 진입/미지원 안내, 닫기 후 이야기 복귀 확인.
- 실제 NFC 카드 표시·실기기 AR 배치/사진·공유 및 운영 API 검증은 미수행.

## 원격 캐릭터 경량화 — 2026-10-16

사용자 요청으로 모든 캐릭터의 원격 배포용 경량본을 `apps/ios/RemoteAssets/CharactersLite`에 생성했다. 개별 크기는 약 3.25~3.71MB이며 원본은 보존한다. 외부 다운로드 방식과 Clip 타깃 리소스 구성은 유지한다. 운영 CDN에 올린 뒤 스토리 API의 URL과 manifest SHA를 함께 갱신해야 적용된다. [경량화 결과·비교·배포 방법](../RemoteAssets/CharactersLite/OPTIMIZATION.md)을 참고한다.
