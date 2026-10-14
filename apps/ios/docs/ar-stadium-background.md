# AR 경기장 배경 실시간 미리보기 — #72

- 구현일: 2026-10-14
- 기준 브랜치: develop (`5669ca1`)
- 작업 브랜치: `feat/#72-ar-stadium-background`
- 상태: 구현·Simulator 빌드·GPU 합성 검증 완료. 실제 iPhone의 벤치 인식 품질·프레임 속도·발열은 미검증.

## 사용 방법

1. 앱 카메라 → 상단 타이머/비율/필터 버튼 → 사진 설정에서 **경기장** 선택.
2. 화면에 보이는 **실제 벤치**를 터치한다. 사람은 자동 분리한다. 벤치 선택 중에는 바닥 탭 재배치보다 벤치 선택을 우선한다.
3. ‘경기장 배경 · 벤치와 사람 유지 중’을 확인한 후 촬영한다. 캐릭터를 아직 배치하지 않았더라도 경기장 사진 촬영은 가능하다.
4. 다른 벤치를 남기거나 추적이 끊기면 사진 설정 → **남길 벤치 다시 선택**을 누른다.
5. **원본**으로 전환하면 기존 AR 카메라로 복귀한다. 비디오 모드로 전환하면 배경 교체를 해제한다. 배경 교체는 이번 변경에서 사진 전용이다.

## 처리 구조

- `ARSessionController`는 ARFrame을 제공하고, `ARStadiumBackgroundService`는 하나의 직렬 작업 큐에서 Vision을 실행한다. 별도 AVCaptureSession을 시작하지 않는다.
- `ARFrame.displayTransform`으로 카메라 이미지를 **전체 ARView의 시점·aspect-fill**에 맞춘다. Vision 입력은 긴 변 512px로 줄인다. 선택 좌표도 동일한 화면 좌표계를 사용한다.
- `VNGenerateForegroundInstanceMaskRequest`의 인스턴스 마스크에서 터치한 피사체를 선택한다. 이후 매 요청에서 마스크 겹침으로 새 인스턴스를 대응한다. Vision의 프레임별 ID를 고정된 물체 ID로 취급하지 않는다.
- `VNGeneratePersonSegmentationRequest(.balanced)`는 재사용하며, 사람 마스크와 선택한 벤치 마스크를 최대값으로 합친다.
- RealityKit postprocess의 렌더링 색상·깊이와 마스크를 Metal에서 합성한다. 카메라 feed는 유지하고, 마스크에 포함된 실제 피사체 및 렌더링 깊이가 있는 AR 캐릭터를 남긴다. 나머지를 경기장으로 교체한다.
- 경기장 모드에서는 재구성 메시의 occlusion과 grounding shadow를 적용하지 않는다. 바닥 메시가 전경 깊이로 인식되어 원래 배경을 남기는 것을 방지한다. 원본 모드 복귀 시 기존 조명·가림 설정을 다시 적용한다. 사람 AR occlusion은 기존 설정을 따른다.
- Shader는 번들 `ARStadiumComposite.metalSource`에서 장치 준비 시 한 번 컴파일한다. 추가 Metal Toolchain 설치 없이 앱 빌드가 가능하다.

## 지연·실패·수명 관리

- Vision 작업은 한 번에 하나만 실행한다. 분석 요청은 최대 10회/초로 제한하고, 처리 중인 프레임이 있으면 새 프레임을 버린다. 실제 분석 빈도나 렌더링 30fps를 보장하지 않는다.
- 0.6초 이상 오래된 마스크, 카메라 이동 8cm 이상 또는 회전 약 4도 이상인 이전 마스크는 합성에 사용하지 않고 **원본 화면**을 표시한다. 이 기준은 초기값이며 iPhone 측정 후 조정한다.
- 인식 실패 시 원본 화면으로 복귀하고 다시 선택하도록 안내한다. 어떤 물체를 벤치로 선택했는지는 의미적으로 분류하지 않으므로 사용자가 선택한 전경 물체를 보존한다.
- 화면 비율·기기 회전 등 viewport/display transform 변경은 선택과 마스크를 초기화한다. 방향 변경 후 벤치를 다시 선택해야 한다.
- 세션 중단·백그라운드·닫기·배경 전환은 세대 번호를 변경해 오래된 비동기 결과를 무시하고 대기 촬영을 취소한다. 복귀 후 다시 선택한다.
- 카메라 영상·마스크는 서버로 전송하거나 중간 파일로 저장하지 않는다.

## 촬영 일치

- 경기장 사진은 ARView의 원본 snapshot 대신 **다음 유효한 postprocess 출력 텍스처**를 복사한다.
- GPU 명령 완료 후 CGImage로 변환하고, 기존 촬영 창의 crop과 선택한 사진 필터를 적용한다. UI 오버레이는 사진에 포함하지 않는다.
- 촬영 타임아웃은 3초이며 원본 사진으로 조용히 대체하지 않는다. 취소/실패하면 안내한다.
- 사진 메타데이터는 기존 방식처럼 촬영 요청 직전에 수집한다. GPU 프레임과 카메라·앵커 메타데이터의 완전한 시각 동기화는 보장하지 않는다. 캐릭터 미배치 사진의 앵커 배열은 비어 있다.

## 경기장 에셋

- `Assets.xcassets/StadiumBackground.imageset/stadium.jpg`
- 내장 image_gen 도구로 만든 가상의 경기장이다. 특정 FIFA 경기장이나 공식 라이선스 이미지를 표현하는 에셋이 아니다.
- 생성 프롬프트: “Photorealistic soccer World Cup scale stadium seen from the middle of the pitch, eye-level 1.5m, diffuse daylight, portrait 3:4, empty grass foreground for real people and a bench overlay; no players, benches, balls, logos, text or watermark.”
- 정적 2D 배경이며 중심 aspect-fill을 사용한다. 360도 회전·6DoF 시차·조명 일치·그림자 재생성은 포함하지 않는다.

## 검증

- iOS Simulator Debug 빌드 통과.
- `sh apps/ios/Tests/run-ar-background-checks.sh`: 실제 Mac Metal GPU에서 카메라 좌표 변환·portrait 회전·벤치 선택/ID 변경·추적 손실·전경/가상 캐릭터 보존·soft mask 경계·배경 교체·원본 복귀·저장 이미지 방향 검증 통과.
- `sh apps/ios/Tests/run-architecture-checks.sh`: 기존 도메인/라우팅 검증 통과.
- iPhone 17 Pro Simulator에서 카메라 진입, 사진 설정 배경 전환, 벤치 재선택 버튼 확인. Simulator에서는 AR 실시간 입력을 검증할 수 없다.

### iPhone 확인 항목 — 아직 수행하지 않음

- 실제 벤치 전경 인식, 등받이 틈·다리·명패·사람이 가리는 부분
- 사람 단독·여러 사람·머리카락·빠른 움직임·벤치와의 겹침
- 후면 카메라의 세로·가로 전환 및 세 가지 사진 비율의 미리보기/저장 구도
- RealityKit 실제 깊이 clear 값과 캐릭터/사람 가림 처리
- 사람·벤치 선택 유지율, 분석 p50/p95 지연, FPS, 배터리·발열, 5분 연속 촬영
- 잠금·핀치·회전·높이 조절·캐릭터 변경·타이머·필터와의 조합
- 권한 거절, 앱 백그라운드/복귀, 세션 오류, 취소/타임아웃

벡터/사각형 마스크로 벤치를 대체하지 않는다. 벤치가 전경으로 검출되지 않는 장면에서는 이 구현으로 사용할 수 없으며, 벤치 전용 모델·추적/사용자 마스크 보정은 후속 검토 항목이다.

## Apple 공식 자료

- [Foreground instance mask](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)
- [People in images and video](https://developer.apple.com/documentation/vision/applying-matte-effects-to-people-in-images-and-video)
- [Lift subjects from images — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10176/)
- [ARKit Metal camera display](https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal)
- [RealityKit Metal postprocess](https://developer.apple.com/documentation/realitykit/implementing-postprocess-effects-using-metal-compute-functions)
