// Keep older clients' URLs callable without reading a submission or calling an AI provider.
export function donationEvidenceRetired(): Response {
  return Response.json({ error: "donation_evidence_retired" }, {
    status: 410,
    headers: { "Cache-Control": "no-store" },
  });
}
