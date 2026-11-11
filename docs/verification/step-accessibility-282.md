# STEP 접근성 표시와 독립 회귀 검사 복구 — #282

2026-11-11. 최신 `develop`을 기준으로 재현한 화면과 검사 실행 오류를 수정한다. 제품 정책·저장 형식·서버·개인 서명 설정은 변경하지 않는다.

## STEP 표시

`OiCreationProgressHeader`는 일반 글자 크기에서 기존 66pt 발자국과 네 단계 가로 배치를 유지한다. 접근성 글자 크기에서는 두 열 안에 텍스트 높이를 따라 늘어나는 둥근 배경을 표시한다. 단계 번호와 제목은 줄바꿈을 허용하며 축소하지 않는다. 열의 상단을 맞추고 단계 간격을 확보한다.

현재 단계의 밝기·누름 애니메이션, 움직임 줄이기 처리, 접근성 라벨과 단계 이동 조건은 기존 구현을 사용한다.

## 검사 스크립트

| 명령 | 실패 원인 | 수정 |
| --- | --- | --- |
| `run-oi-service-checks.sh` | 기부 자료 접수 종료 후 삭제된 운영자 파일 참조 | 삭제된 두 입력을 제거하고 현재 `StoryCard`를 포함. 모듈 캐시도 검사 전용 임시 폴더에서 정리 |
| `run-draft-recovery-checks.sh` | `OiServiceModels`의 카드 경로 의존성 누락 | 실제 `StoryCard.swift`를 컴파일 입력에 포함 |
| `run-draft-adoption-checks.sh` | 같은 의존성 누락 | 실제 카드 모델 포함 |
| `run-account-connection-flow-checks.sh` | 같은 의존성 누락 | 실제 카드 모델 포함 |

가짜 카드 타입을 만들거나 검사 항목·실패 조건을 삭제하지 않는다. 기존 기부 자료의 비공개 보관·재개 식별자를 검사하는 호환성 사례도 유지한다.

macOS에서 다음 명령을 실행한다.

```sh
sh apps/ios/Tests/run-oi-service-checks.sh
sh apps/ios/Tests/run-draft-recovery-checks.sh
sh apps/ios/Tests/run-draft-adoption-checks.sh
sh apps/ios/Tests/run-account-connection-flow-checks.sh
```

## 검증

- 위 검사 4개 통과. 서비스 요청·카드 조작·사진/초안 보존, 손상 자료 복구, 계정별 초안 이관 충돌, 계정 연결 취소·상태 전이를 실제 프로덕션 타입으로 검사했다.
- iOS 27.2 / iPhone 18 Pro Simulator에서 `OiFlowChecks` XCTest 116개 통과, 실패 0. 별도 수동 조작을 기다리는 opt-in 검사 3개는 기본 설정대로 건너뛰었다.
- `OiRemoteStoreTests`, `OiPhotoImportTests`, `OiPhotoCropTests`, `OiCostumePhotoTests`, `OiWardrobeAssetTests`, `CampusMapInteractionTests`와 이야기 작성·약관·오이/카드 완료 화면 캡처를 재실행했다. 사진 순서·크롭·회전·PNG 가져오기·꾸미기 복원과 지도 조작도 통과했다.
- 375×667·402×874·440×956 일반 크기와 402×874 최대 접근성 크기를 렌더링했다. 캡처 검사는 렌더링 성공을 확인하므로 PNG도 직접 검사해 STEP 번호가 배경 밖으로 나가지 않고 제목이 겹치지 않는지, 일반 크기의 발자국이 유지되는지 확인했다.
- 가상 계정·테스트 백엔드를 사용한다. 현장 AR·GPS, 실제 Apple/Google 로그인·운영 DB 왕복은 이 수정의 검증 범위 밖이다.
