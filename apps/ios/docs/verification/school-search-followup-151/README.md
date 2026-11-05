# 학교 검색 결과 없음 — 2026-11-05

[Figma 4340:13281](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=4340-13281)의 학교 검색 0건 시안을 적용했다.

- 57pt 검색창, 좌우 20pt 여백, Paperlogy Semibold 18pt 입력란과 오른쪽 돋보기를 사용한다. 별도 내비게이션 행 없이 시스템 시트 내리기와 VoiceOver 닫기를 제공한다.
- 기존 CampusSearchNoResults 캐릭터를 192×300pt로 표시한다. Figma 원본과 번들 이미지 SHA-256은 모두 b20e7e3af0a7a59e241692f86597df343cddc2437489d672375b3b156578cb6b다.
- 문구는 “해당 이름을 가진 학교가 없습니다 / 학교이름이 정확한지 한번 더 확인해주세요”. Paperlogy Medium 18pt, 줄 높이 27pt, 자간 0.36pt, OiGreen을 사용한다. 캐릭터와 문구 사이 간격은 16pt다.
- 검색어가 없으면 기존 POSTECH 카드를 표시한다. POSTECH·포스텍·포항공과대학교 검색과 학교 선택 조건을 유지한다. 제공 중인 캠퍼스 검색이며 학교 인증 목록과는 별개다.

## 검증

Xcode 27.2 / iPhone 18 Pro Simulator(iOS 27.2)에서 본 앱·App Clip 빌드와 OiFigmaFidelityVisualTests/testSchoolSearchEmptyResultCaptures 1개가 통과했다. 기본·소형·대형·최대 접근성 글자 크기의 결과 없음과 최초 진입·일치 결과 총 6개 화면을 캡처했다. 캐릭터 영역의 녹색 픽셀도 확인한다.

- [기본 402×874](school-search-no-matches-402x874.png)
- [소형 375×667](school-search-no-matches-375x667.png)
- [최대 접근성 글자 크기](school-search-no-matches-accessibility5.png)
- [최초 진입 POSTECH 카드](school-search-initial-402x874.png)

캡처는 실제 SwiftUI 뷰와 가상 검색어를 사용한다. 시스템 상태바·홈 인디케이터는 포함되지 않는다. 실제 iPhone 설치·키보드 및 시트 내리기 조작 검증은 진행하지 않았다.
