# 캐릭터 카메라 (#8)

## 범위

`/camera`는 DB 없이 동작하는 클라이언트 촬영 페이지다. 소개와 이야기 상세에 진입 링크를 추가했다.
공식 POSTECH/KAIST GLB는 아직 제공되지 않았고 임시 모델임을 화면에 표시한다. `apps/web/public/models/README.md`를 따라 교체한다.

- 전/후면 카메라, 개별 캐릭터 선택·표시, 두 캐릭터 동시 표시
- 드래그 이동, 핀치 확대, 크기·방향·위치 슬라이더
- 인물 분할 옵션: 모든 인물 영역을 캐릭터 앞에 합성 (실제 깊이·물체 가림 아님)
- 미리보기와 같은 720×960 구도로 JPEG 촬영, 다운로드·기기 공유·재촬영
- 서버 사진 저장 없음. 탭을 숨기거나 페이지 종료·촬영 시 카메라와 작업 스레드 해제

## 구성

- `camera-experience.tsx`: 카메라 수명, Canvas 합성, 조작 UI, 촬영/공유
- `character-scene.ts`: Three.js 조명, GLB 로드·정규화·자원 정리, 임시 모델
- `person-segmentation.worker.ts`: MediaPipe IMAGE 추론을 Worker에서 실행
- `composition.ts`: 카메라 중앙 크롭·전면 미러링과 배치 타입

3D 렌더는 매 프레임 수행하며 분할은 최대 10회/초 요청한다. Worker에 전송한 프레임과 마스크를 한 쌍으로 유지해 배경 영상과 인물 윤곽의 시차를 방지한다. 가림 모드는 추론 속도만큼 영상 갱신이 느려질 수 있다. 로드 실패/추론 오류/시간 초과 시 일반 합성으로 복귀한다.

정적 MediaPipe WASM, 모델, Draco 디코더를 public에 포함했다. 버전 업데이트 시 npm 패키지와 WASM을 함께 갱신해야 한다. 카메라 정책을 `camera=(self)`로 변경했고 마이크·위치는 계속 미사용이다.

## 실행 및 검사

루트에서 `npm ci`, `npm run dev` 후 http://127.0.0.1:3000/camera 에 접속한다. 인물 분할 Worker까지 일치하는 검증은 프로덕션 빌드로 수행한다.

```
npm run lint
npm run typecheck
npm test
npm run build
node node_modules/next/dist/bin/next start apps/web --hostname 127.0.0.1 --port 4318
# 다른 터미널, apps/web 폴더에서:
TEST_BASE_URL=http://127.0.0.1:4318 ../../node_modules/.bin/playwright test tests/browser/camera.spec.ts
```

카메라 테스트는 Chrome 가상 영상으로 실행되며 DB가 필요 없다. 기존 이야기 통합 테스트는 별도 테스트 DB가 필요하다.

## 현장 전 확인

자동 테스트 통과는 iPhone/Android 실기기 검증을 대체하지 않는다. HTTPS 테스트 주소에서 확인한다.

- iPhone Safari, Android Chrome의 권한 허용/거부/재진입
- 후면·전면 전환, 저장 사진과 미리보기 구도·좌우 방향
- 두 캐릭터 GLB 정면·옆·뒷면, 드래그·핀치·회전
- 1인/여러 사람/머리카락/빠른 움직임에서 가림 품질 및 발열
- 공유 취소·공유 미지원 시 다운로드, iPhone 사진 길게 누르기 저장
- 카카오톡 인앱 브라우저에서 실패하면 Safari/Chrome으로 열기

실제 서버 배포와 공식 캐릭터 삽입은 아직 하지 않았다. 라이브 기부 DB를 사용한 테스트는 실행하지 않는다.
