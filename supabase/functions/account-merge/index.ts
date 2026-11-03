import { createHandler } from "./handler.ts";

Deno.serve(createHandler({
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  publicKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
}));
