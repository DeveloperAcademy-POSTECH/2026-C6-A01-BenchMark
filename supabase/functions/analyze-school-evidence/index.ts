import { createSchoolHandler } from "./handler.ts";

Deno.serve(createSchoolHandler({
  enabled: Deno.env.get("OI_SCHOOL_EVIDENCE_AI_ENABLED") === "true",
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  supabaseKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  openaiKey: Deno.env.get("OPENAI_API_KEY") ?? "",
  model: Deno.env.get("OPENAI_EVIDENCE_MODEL") || undefined,
}));
