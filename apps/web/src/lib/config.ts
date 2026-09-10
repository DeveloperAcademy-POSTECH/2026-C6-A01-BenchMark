export function collectionPolicy() {
  const mode = process.env.REGISTRATION_MODE ?? "test";
  if (mode !== "test" && mode !== "live") throw new Error("Invalid collection mode");
  const retentionDays = mode === "test" ? 7 : Number(process.env.PRIVACY_RETENTION_DAYS);
  const contact = process.env.PRIVACY_CONTACT_EMAIL ?? "";
  if (mode === "live" && (!Number.isInteger(retentionDays) || retentionDays < 1 || retentionDays > 365 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contact))) {
    throw new Error("Live collection policy is not configured");
  }
  return { mode, retentionDays, contact };
}
