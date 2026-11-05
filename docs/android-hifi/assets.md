# 후속 hi-fi 에셋 출처

원본은 [Figma 프로토타입](https://www.figma.com/design/nEDJaJBFrdzBCa1WcgADHH/BenchMark?node-id=795-1610)의 get_design_context가 제공한 에셋이다. 앱에는 만료되는 Figma 다운로드 URL을 남기지 않는다. PNG 원본은 바이트 변경 없이 복사했고 SVG는 bundled sharp/librsvg로 4배 PNG를 렌더링했다. Android의 drawable-nodpi에 저장하고 Figma 논리 크기에 맞춰 표시한다.

| Android drawable | 원본 파일 | Figma frame / slot |
| --- | --- | --- |
| onboarding_yes | 3ff99.svg (173×205) | 820:1830 / O버튼 |
| onboarding_no | 51836.svg (173×205) | 820:1830 / X버튼 |
| onboarding_cucumber | 6ba7d.svg (25×31) | 820:1830 / 온보딩 질문 |
| story_campus | 91edc.png | 1173:928, 1239:1379 / 캠퍼스 카드 |
| story_birthday | 2c861.png | 1173:928, 1239:1379 / 생일 카드 |
| story_view | 3a5fd.png | 1239:1379 / 포스텍 풍경 |
| story_lake | a84c0.png | 1239:1379 / 지곡회관 |
| story_sea | ba59f.png | 1239:1379 / 바다 |
| story_map | 5383e.png | 1173:928 / 지도 카드 뒤면 |
| story_card_background | 63d66.png | 1173:928 / 1264:2368 |
| story_bench | 6774f.png | 1173:928 / 1264:2393 (132×75) |
| story_bench_shadow | eb6d6.svg (238×86) | 1173:928 / 1264:2392 |

카드 사진은 예시 선택과 명시적 디자인 사례 로딩에만 사용한다. 계정이나 실제 기부자의 사진으로 표시하지 않는다. `ic_camera.xml`, `ic_grid.xml`은 Android용 네이티브 벡터다. 기존 홈 에셋은 그대로 재사용한다.
