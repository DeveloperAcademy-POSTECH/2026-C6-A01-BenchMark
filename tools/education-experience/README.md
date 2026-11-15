# 교육지구 오프라인 웹 체험 번들

이슈 #365의 앱 내 체험 자산을 검토한 독립 웹 스냅샷에서 가져온다. 독립 웹의 개발·배포는 #293에서 별도로 관리한다. 이 도구는 캠퍼스 지도 형상이나 원본 웹을 수정하지 않는다.

## 자산 갱신

저장소 루트에서 실행한다. 일반 앱 빌드에는 이 명령이나 Node 설치가 필요하지 않다.

```sh
npm ci --prefix tools/education-experience --ignore-scripts
npm --prefix tools/education-experience run build -- /path/to/reviewed/dist
```

입력은 `index.html`, 두 ES 모듈 진입점, CSS, Three.js, 모델/이미지/폰트를 포함한 검토 완료 dist다. 현재 스냅샷은 2026-11-15 정원·진주 건물 `education-pearl-texture-screen-v30`이다. `building-v25`는 원본 폴더명이며 모델 버전은 JSON의 revision으로 확인한다. 원본 HTML 해시와 파일별 해시·크기는 출력 manifest에 남긴다. 개인 경로는 모델 메타데이터에서 파일명만 남긴다.

출력은 `apps/ios/OiDonation/Resources/Campus/`의 HTML, `education-light-assets.json`, 콘텐츠 해시가 붙은 24개 자산이다. Three.js와 Pretendard 라이선스를 함께 포함한다. 오래된 해시 자산만 제거하며 기존 지도 바이너리는 보존한다. 파일 시스템 동기화 Xcode 그룹의 리소스 평탄화에도 충돌하지 않는 이름을 사용한다.

웹 PNG는 번들 파일명을 `.bin`으로 두고 manifest의 `image/png` MIME으로 제공한다. iPhoneOS의 `CopyPNGFile`이 `.png`를 CgBI 형식으로 변환하지 않도록 원본 바이트를 보존하기 위한 처리다. 원래 요청 경로와 이미지 내용은 유지한다. 실기기 빌드 후에도 manifest의 SHA-256·크기와 실제 번들 파일이 모두 일치하는지 확인한다.

## 네이티브 연결과 검증

`EducationLightWebModel`이 기존 파일 URL로 HTML을 읽고, `oi-education://bundle/` 요청은 manifest 허용 경로만 제공한다. 스크립트·스타일은 인라인으로 묶어 로컬 파일 ES 모듈 제약과 외부 CDN 의존을 없앤다. CSP는 네트워크 요청을 차단한다. 준비/오류·비활성 메시지를 네이티브 로딩/재시도/수명 주기에 연결한다. 예시·기기 저장은 실제 이야기 공개나 기부 집계가 아니다.

갱신 후 `OiFlowChecks` 스킴의 `CampusEducationDistrictTests`를 실행한다. 번들 파일 누락·허용 경로 경계, 실제 WKWebView/WebGL 로드, 모델 버전·진주 개수와 네이티브 일시 정지/재개를 확인한다. 시뮬레이터에서 교육지구 안내 → 체험 → 빛 흩어보기/돌아오기 → 닫기 → 지도 복원도 확인한다. 실제 iPhone의 장시간 발열·프레임률은 별도 확인이 필요하다.
