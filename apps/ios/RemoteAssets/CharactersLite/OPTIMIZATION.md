# 원격 다운로드용 캐릭터 경량화

2026-10-16 / #79. 원본은 보존하고 외부 다운로드 방식을 유지한다. 이 폴더를 앱이나 Clip의 Target Membership에 추가하지 않는다.

| 캐릭터 | 원본 | 경량본 | 감소 |
| --- | ---: | ---: | ---: |
| 넙죽이 | 14.17MB | 3.44MB | 75.7% |
| 넙죽이 애니메이션 | 14.23MB | 3.51MB | 75.3% |
| 포닉스 | 63.87MB | 3.63MB | 94.3% |
| 포닉스·넙죽이 대결 | 12.26MB | 3.25MB | 73.5% |
| 도니 | 32.84MB | 3.71MB | 88.7% |

## 처리와 검증

- 텍스처는 최대 1024px, JPEG 품질 88(4:4:4), PNG 채널 유지. 근접 확대 시 세부 질감과 작은 글자의 선명도는 감소할 수 있다.
- 넙죽이는 USD 장면과 메시를 그대로 유지했다.
- 애니메이션 넙죽이는 뼈대·모션·메시를 유지했다. 원본의 기존 노멀맵 scale/bias 누락만 경량본에서 보정했으며 해당 재질 블록 외의 USD 텍스트가 동일함을 검사했다.
- 포닉스·도니·대결 모델은 약 10만 삼각형으로 줄였다. UV·노멀 이음매는 분리 정점으로 보존하고 원래 재질·축·단위·계층을 유지했지만 미세 실루엣 변화는 가능하다.
- 모든 파일은 Apple `usdchecker --arkit`, USDZ 64바이트 정렬·무압축, 원본/결과 SHA, Mac RealityKit 실제 로드 검사를 통과했다. 일부 정적 모델의 기존 occlusion 상수 경고는 남아 있다.
- 원본 대비 bounds 2% 이내와 애니메이션 수 일치를 검사했다. 실제 iPhone의 근접 품질·애니메이션·발열/FPS는 추가 확인이 필요하다.
- `quality-comparison.jpg`는 같은 USD 렌더러로 본 원본(왼쪽)/경량본(오른쪽)이다. 애니메이션 기본 포즈·카메라·스키닝 결과는 렌더러에 따라 다르므로 최종 동작은 RealityKit 실기기에서 확인한다.

## CDN 적용

1. 사용할 `*-lite-v1.usdz`를 승인된 HTTPS CDN에 업로드한다. 이번 작업에서는 업로드하지 않았다.
2. 스토리 API의 `character.asset.url`을 실제 파일 주소로, `sha256`을 `manifest.json`의 동일 파일 값으로 함께 갱신한다.
3. `OI_CLIP_ASSET_HOSTS`에 최종 파일 호스트를 등록한다. 리디렉션 없는 URL을 사용한다.
4. 재수정 시 v2 등 새 파일명을 사용해 CDN 캐시와 해시 불일치를 피한다. 운영 API가 원본 URL을 반환하는 동안에는 앱도 원본을 받는다.

경량 모델의 합계는 약 17.54MB다. 외부 다운로드용이므로 Clip 번들은 늘어나지 않으며, 모든 모델을 내장했을 때 15MB 제한을 충족한다는 의미가 아니다.

## 재현 및 다운로드 테스트

Pillow가 설치된 Python, Blender 4.5 LTS, Apple USD 도구를 사용한다. 별도의 백그라운드 Blender 프로세스이므로 사용 중인 장면은 바꾸지 않는다.

```sh
python3 apps/ios/Tools/optimize-characters.py
sh apps/ios/Tests/run-character-lite-checks.sh
```

App Clip의 로컬 다운로드 테스트에는 다음 경량 파일을 지정한다.

```sh
python3 apps/ios/Tests/Fixtures/clip-content-server.py \
  --model apps/ios/RemoteAssets/CharactersLite/neopjuk-lite-v1.usdz \
  --image apps/ios/OiDonation/Assets.xcassets/HomeBench.imageset/HomeBench.png
sh apps/ios/Tests/run-appclip-content-checks.sh
```
