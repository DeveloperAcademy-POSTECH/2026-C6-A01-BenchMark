# 포항시 경계 데이터

[국가데이터처 SGIS 행정구역 통계 및 경계_20250630](https://www.data.go.kr/data/15129688/fileData.do)의 공개 원본 중 2025년 2분기 기준 시군구 경계를 사용한다. 공공데이터포털은 이 자료의 이용허락범위를 ‘제한 없음’으로 표시한다. 내려받은 ZIP의 SHA-256은 `f1cf0f9de453ac7eaacb273f39cee52851183372b9ddfda428a967c3a670b2c6`이다.

원본 레이어는 `bnd_sigungu_00_2025_2Q`다. `BASE_DATE=20250630`인 포항시 남구(`SIGUNGU_CD=37011`)와 포항시 북구(`37012`)를 사용한다. 두 구의 원본 291개 외곽 링은 내부 홀을 포함하지 않는다. 공통 경계의 반대 방향 선분 917쌍을 제거해 구 사이에 가짜 시 경계가 생기지 않도록 한다. 합친 면적과 닫힌 외곽 링을 검사하며 섬과 해안선을 유지한다. [포항시 행정구역](https://jp.pohang.go.kr/portal/contents.do?mid=0402050000)

변환은 원본의 [EPSG:5179](https://link.mods.go.kr/view/newhelp/us_help_30_0)에서 횡축 메르카토르 역변환을 거쳐 WGS84 경도·위도 순서의 GeoJSON을 만든다. [USGS 지도 투영 매뉴얼](https://pubs.usgs.gov/publication/pp1395)의 횡축 메르카토르 수식을 사용한다. 도형 단순화는 하지 않는다. 결과는 290개 폴리곤, 닫힌 링의 시작과 끝을 포함해 57,404개 좌표다. 파일 SHA-256은 `5b5e99a6b81ee75eda4ace10965c3fa1eee61cc9a1a281a57d991f3ec49e93b3`이다.

```sh
python3 tools/campus/extract_pohang_boundary.py '<다운로드한 SGIS ZIP>' apps/ios/OiDonation/Resources/pohang-city-boundary.json
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh apps/ios/Tests/run-campus-card-location-checks.sh
```

판정은 iOS 기기에서 최근 위치 한 건과 Core Location의 수평 오차를 사용한다. 좌표계 변환의 근사치와 반올림을 고려해 2m를 추가하며, 이 범위가 경계에 닿으면 다시 확인한다. 판정에 쓴 좌표는 서버로 보내거나 저장하지 않는다. 이 경계는 통계 기준일의 시군구 도형이며 갱신은 후속 SGIS 배포본을 확인해 진행한다.
