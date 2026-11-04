# iOS·App Clip 빈 화면 확인 — 2026-11-04

실제 실행 경로를 [Figma 프로토타입 ver.2](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2339-2109)의 지도, 이야기 작성, MY, AR 섹션과 대조했다. 아래 목록에는 조회 성공 후 0건, 입력 전 상태, 콘텐츠 누락을 각각 표시했다. 실패·권한·인증은 마지막 표에서 구분한다.

## Figma에서 빈 상태를 정의한 곳

| 화면 | 원본과 앱 |
| --- | --- |
| 내 농장 · 등록한 오이 0개 | [Figma 빈 농장](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2876-7298)의 오이 이미지, 제목, CTA를 사용한다. 기부·작성 승인 안내는 현재 제품 규칙을 따른다. |
| 이야기 목록 · 빈 슬롯 | [Figma 이야기 목록](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2935-1170)에 개별 `+` 빈 슬롯이 있다. 앱은 이야기 0건에도 같은 슬롯을 사용한다. 전체 0건과 비로그인 전용 화면은 Figma에 없다. |

## 별도 빈 상태 디자인이 없는 곳

| 화면 | 실제로 비어 있는 조건 | 현재 표시 |
| --- | --- | --- |
| 받은 카드 요청 | 조회 성공, 대기 요청 0건 | 시스템 봉투 아이콘과 “받은 카드 요청이 없어요”. [Figma 요청함](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=3658-3059)은 요청이 있는 화면만 보여 준다. |
| 캠퍼스 전체 지도 | 공개 오이 0개 | 3D 지도와 지역별 개수. 전체 0개 전용 화면이 없다. [Figma 전체 지도](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=3294-3164) |
| 선택 지역·이 지역 재검색 | 지역 또는 현재 지도 범위의 이야기 0건 | 목록에 0건 안내를 표시한다. [Figma 지역 목록](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2379-4041) |
| 오이 검색 | 이름·기부자·코드가 일치하지 않음, 또는 공개 오이 자체가 0개 | 검색 결과 없음 또는 공개 오이 0개 안내. 기부자·코드 입력 전에는 결과 영역을 비운다. [Figma 검색](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=3739-3765) |
| 학교 검색 | POSTECH과 일치하는 검색 결과 0건 | 시스템 검색 결과 없음. [Figma 학교 검색](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2544-9010) |
| MY 도감 · 전체 | 계정 도감과 App Clip 도감에서 표시할 카드 0개 | 수집한 카드가 없다는 안내. App Clip 카드가 있으면 전체 0개 안내를 생략한다. [Figma 도감](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2510-5695) |
| MY 도감 · 즐겨찾기 | 고정한 카드 0개 | 즐겨찾기 안내. 학교 필터가 적용돼도 별도 전용 화면은 없다. |
| MY 도감 · 학교별 | 학교 폴더 0개 또는 선택한 학교의 카드 0개 | 도감의 공통 안내. [학교별 폴더](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2558-9881), [학교 내부](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2558-10110) |
| 이야기 작성 · 사진 | 선택한 사진 0장 | 사진 선택 안내와 사진 추가 동작. [Figma 이야기 사진](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=3504-13187)은 사진을 고른 상태다. |
| 이야기 작성 · 위치 | 장소 미선택, 장소 검색 결과 0건 | 선택 안내 또는 시스템 검색 결과 없음. [Figma 장소 검색](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=3504-13188), [Figma 지도 선택](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=3517-13491) |
| 오이 옷장 · 사진 레이어 | 추가한 의상 사진 0장, 선택한 레이어 없음 | 사진을 추가할 수 있는 편집기. 레이어 조작은 선택 시 표시한다. [Figma 의상 사진](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=4158-9340) |
| 카드 꾸미기 · 세트 | 선택 가능한 공개 카드 세트 0개 | 세트가 없다는 안내. [Figma 카드 꾸미기](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2945-3003) |
| 공개 이야기 · 콘텐츠 일부 없음 | 사진·관련 이야기·본문·위치 중 일부 없음 | 사진과 관련 이야기 섹션은 생략한다. 본문과 위치에는 각각 안내를 표시한다. [Figma 이야기 상세](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2450-4928) |
| MY 설정 · 계정 정보 | 학교 미선택, 학교 목록 0건, 프로필 데이터 없음 | 학교 선택 안내·학교 목록 0건 안내·기본 닉네임을 사용한다. 농장 이름은 현재 농장 제목을 표시한다. [Figma 설정](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2835-2654) |

## 데이터 0건과 구분하는 화면

| 분류 | 해당 화면과 조건 |
| --- | --- |
| 조회·연결 실패 | 지도, 오이 검색, 도감, 농장, 이야기 목록·초안, 요청함. 기기에 남은 App Clip 카드가 서버에서 열리지 않으면 도감의 연결 대기 항목으로 보인다. 운영 Supabase에는 2026-11-04 확인 시 `oi_card_requests()`와 `oi_resolve_card_request(uuid,text)`가 설치돼 있지 않아 카드 요청함은 조회 오류 분기로 들어간다. 정상 응답이 0건일 때의 화면은 위 표와 같다. |
| 인증·권한·작성 자격 | 비로그인 요청함, 농장, 설정, 작성·수집 경로와 재인증. 작성 승인 없음, 카메라·위치 권한 거부와 AR 미지원은 이용 조건 안내다. |
| 열었던 기록을 다시 읽을 수 없음 | 공개 취소·삭제된 이야기, 읽을 수 없는 기기 초안, 관리 대상 이야기가 사라진 경우. 공개 이야기와 현장 AR에서 같은 상황의 빈 화면 대신 기존 이야기 열기 실패 문구를 사용한다. |
| App Clip 진입·미디어 | 기본 호출 안내, 잘못된 링크, 공개 이야기 없음, 이야기 조회 실패, AR 미지원. 카드 이미지 URL이 없으면 실제 이야기로 카드를 합성하고, 이미지 다운로드 실패에는 재시도를 제공한다. 공개 링크 호스트는 본 앱과 App Clip에 연결돼 있지 않다. |
| AR 게임 실패 | 제한 시간 안에 수집하지 못한 경우는 데이터가 없는 화면과 별개다. [Figma 게임 실패](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH?node-id=2869-7163)가 있다. |
