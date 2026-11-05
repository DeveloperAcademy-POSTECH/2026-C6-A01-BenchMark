# 카드 요청 알림 디자인 — 2026-11-05

[Figma 4228:11025](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=4228-11025)를 기준으로 요청 0건 시트를 보완했다.

- 녹색 `#EAEEE2` 70% 배경, 상단 모서리 35pt, 좌우·상단 여백 20pt를 적용한다. 별도 Material과 상단 스크롤 흐림 효과를 중첩하지 않는다.
- 본문은 Paperlogy Medium 21pt, 자간 0.42pt, 줄 높이 31.5pt, 녹색 `#708C40`을 사용한다. 남은 시트 높이에 맞춰 중앙 정렬하고 큰 글자에서는 스크롤한다.
- **사용자 확정:** 30일 보관·자동 삭제 문구와 동작은 제외한다. 안내 자리에는 작은 제목과 닫기 버튼을 유지한다. 시스템 시트 내리기로도 닫을 수 있다.
- 조회·수락·거절·실패 재시도 로직은 그대로다. 로딩·오류·처리 결과 미확인에 빈 상태를 표시하지 않는다.
- 투명도 줄이기·대비 증가 설정에서는 불투명 배경을 사용한다.

## 화면 확인

`OiFigmaFidelityVisualTests/testCardRequestInboxCaptures`로 실제 SwiftUI 뷰를 렌더한다. 기본 402×874, 소형 375×667, 대형 440×956, 최대 접근성 글자 크기에서 목록·빈 상태·오류를 확인하고, 처리 결과 미확인과 Figma 크기 402×803를 추가 캡처한다. 총 14장이다. Xcode 27.2 / iPhone 18 Pro Simulator(iOS 27.2)에서 본 앱·App Clip 빌드와 해당 XCTest 1개가 통과했다.

원본 크기 캡처는 어두운 비교용 배경 위의 시트 콘텐츠다. 실제 지도·계정 데이터나 시스템 시트 외곽을 캡처한 것은 아니다. 실제 화면에서는 아래 지도에 따라 반투명 배경색이 달라진다. 큰 글자 캡처는 스크롤 시작 위치다.

- [기본 빈 상태](card-requests-empty-402x874.png)
- [Figma 원본 크기·투명도 비교](card-requests-empty-402x803-sheet.png)
- [소형 화면](card-requests-empty-375x667.png)
- [최대 접근성 글자 크기](card-requests-empty-accessibility5.png)

실제 iPhone 설치·실행은 이번 작업에서 진행하지 않았다.
