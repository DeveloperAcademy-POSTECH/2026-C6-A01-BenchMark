# 홈 화면 구현

- 디자인: https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=1021-4493
- HomeView: 로고·벤치 배너·기부 내역·바로가기·참여 현황 구성. Figma 원본 이미지는 Assets.xcassets에 저장했다.
- RootTabView가 탭별 경로와 독립 카메라 버튼을 소유한다. HomeView는 홈 콘텐츠만 담당하며 전체 미리보기는 RootTabView(container: .preview)를 사용한다.
- Preview의 이름과 현황만 HomeDashboard.designExample의 예시 데이터이며 화면에 예시임을 표시한다. 실제 실행은 미연결 현황을 표시한다. 서버·학교 확인 데이터 연동은 아직 없다. 진행률 78%의 산식도 정의하지 않았다.
- 기부와 정기후원은 POSTECH 공식 절차로 안내하며 앱에서 결제를 처리하거나 납입 완료로 기록하지 않는다.
- 알림·프로필·소식·혜택은 안내 화면이다. 내 기부·벤치 목록·참여 신청은 Repository 인터페이스에 연결했으나 실제 서버와 지도는 아직 연동하지 않았다.
- 제공된 프레임에는 배너 한 개만 있으므로 실제 다섯 개 콘텐츠를 가정하거나 작동하지 않는 페이지 점을 표시하지 않았다. 여러 배너의 콘텐츠 확정 후 페이지 컨트롤을 연결해야 한다.
- Griun OMIRI, Pretendard, KIM WILDgag 글꼴 파일은 저장소에 없다. 현재 시스템 글꼴을 사용하며, 사용 권한이 확인된 글꼴 파일을 전달받으면 교체할 수 있다.
- iOS 26.2 이상인 기존 배포 대상에 맞춰 구현했다. 개인 DEVELOPMENT_TEAM 변경은 기존 로컬 상태를 유지했다.
