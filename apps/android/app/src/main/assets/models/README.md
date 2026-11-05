# AR 캐릭터 출처

원본: https://github.com/june6-6/ARTest
원본 커밋: `704ea94bf76dbafd77d90f1645154a71ca19cb4c`
원본 경로: `ARTest/Resources/Characters/<이름>.usdz`

이 작업은 저장소 소유자의 ARTest Android 이식 요청에 따라 제공된 캐릭터를 변환합니다. 원본 저장소는 별도 에셋 라이선스를 부여하지 않습니다. 일반 재배포/재사용 라이선스를 새로 부여하지 않습니다.

- Blender 4.5.1의 USD importer → glTF 2.0 GLB exporter
- `tools/convert_ar_models.py`로 재생성, `tools/check_ar_models.py`로 구조 검증
- 정적 메시: 메시당 최대 약 80,000 삼각형으로 축소
- 애니메이션 모델: 뼈대·가중치·동작 보존을 위해 메시 축소 없음
- 텍스처: 최대 2048px, GLB 내부 포함, 외부 요청 없음
- Y-up, 미터 기반 glTF. 실행 시 높이 1m 기준 정규화 후 사용자 키 적용
- 원본/변환 SHA-256과 크기는 `conversion.json`에 기록

`neopjukAnimated.glb`에는 1개 skin과 1개 animation이 있습니다. 머티리얼/축/애니메이션의 최종 시각적 동등성은 실제 Android 기기에서도 확인해야 합니다.
