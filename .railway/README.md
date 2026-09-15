# Railway 운영 설정

`.railway/railway.ts`는 `benchmark-mat-pilot` 프로젝트의 웹 서비스, PostgreSQL, 영속 볼륨을 정의한다. 공식 SDK는 개발 의존성이므로 `npm ci`로 설치한다.

```bash
railway config plan
railway config apply
```

먼저 연결된 프로젝트와 환경을 확인한다. 계획에서 의도한 서비스 설정만 변경하는지 검토한 뒤 적용한다. 다른 서비스·데이터베이스·변수 삭제가 나타나면 적용하지 않는다.

- 웹의 `preDeploy`는 DB 마이그레이션을 수행한다.
- `/api/health`가 DB와 운영 환경변수를 확인해야 배포가 정상으로 판정된다.
- `preserve()`로 표시된 비밀번호·서명 키·연결 문자열은 Railway에 보관한다. 실제 값을 소스에 넣지 않는다.
- 코드 업로드는 설정 적용과 별개다. `railway up --service mat-web --detach`로 수행한다.
- 새 도메인을 연결할 때 Railway의 `APP_ORIGIN`을 함께 변경한다.
- 자세한 운영 방법은 `docs/MAT-WEB.md`를 참고한다.
