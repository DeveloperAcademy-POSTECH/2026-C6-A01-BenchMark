import { analyzeDocument, DEFAULT_MODEL } from "../functions/analyze-evidence/analysis.ts";

// No donor data or local uploads are read. This PDF exists only in memory.
function syntheticPDF() {
  const lines = [
    "SYNTHETIC TEST - NOT A REAL PAYMENT",
    "DONATION TRANSFER EXAMPLE",
    "Recipient: Fictional Campus Fund",
    "Payer: Test Person (not a real identity)",
    "Amount: KRW 10000",
    "Transfer date: 2026-11-02",
    "Status: Completed (synthetic example)",
    "Generated for API compatibility testing only.",
  ];
  const escape = (value) => value.replace(/[\\()]/g, "\\$&");
  const content = `BT /F1 14 Tf 50 740 Td 24 TL ${lines.map((line) => `(${escape(line)}) Tj T*`).join(" ")} ET`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let pdf = "%PDF-1.4\n";
  const offsets = [0];
  for (const [index, object] of objects.entries()) {
    offsets.push(pdf.length); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  }
  const start = pdf.length;
  pdf += `xref\n0 ${offsets.length}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) pdf += `${String(offset).padStart(10, "0")} 00000 n \n`;
  pdf += `trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n${start}\n%%EOF\n`;
  return new TextEncoder().encode(pdf);
}

if (!process.env.OPENAI_API_KEY) throw new Error("OPENAI_API_KEY is required; do not put the key on the command line.");
const model = process.env.OPENAI_EVIDENCE_MODEL || DEFAULT_MODEL;
try {
  const result = await analyzeDocument({ bytes: syntheticPDF(), contentType: "application/pdf",
    apiKey: process.env.OPENAI_API_KEY, model, signal: AbortSignal.timeout(60_000) });
  console.log(JSON.stringify({ live_api: "passed", synthetic_only: true, model,
    verdict: result.verdict, readability: result.readability, findings_count: result.findings.length,
    authenticity_verified: false }));
} catch (error) {
  console.error(JSON.stringify({ live_api: "failed", code: error.code ?? "unknown", status: error.status ?? null }));
  process.exitCode = 1;
}
