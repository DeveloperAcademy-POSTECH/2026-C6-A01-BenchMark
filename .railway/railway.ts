import { defineRailway, postgres, preserve, project, service, volume } from "railway/iac";

export default defineRailway(() => {
  const Postgres = postgres("Postgres", { region: "us-west2" });
  Postgres.networking = { privateNetworkEndpoint: "postgres" };
  const postgresVolume = volume("postgres-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "us-west2", sizeMB: 5000 });
  const matWeb = service("mat-web", {
    healthcheck: "/api/health",
    healthcheckTimeout: 120,
    preDeploy: "npm run db:migrate",
    replicas: { "us-west2": 1 },
    env: { ADMIN_PASSWORD: preserve(), APP_ORIGIN: preserve(), DATABASE_URL: preserve(), DONATION_ACCOUNT: preserve(), DONATION_ACCOUNT_CONFIRMED: preserve(), DONATION_ACCOUNT_HOLDER: preserve(), DONATION_BANK: preserve(), PORT: preserve(), SESSION_SECRET: preserve() },
  });

  return project("benchmark-mat-pilot", {
    resources: [matWeb, Postgres, postgresVolume],
  });
});
