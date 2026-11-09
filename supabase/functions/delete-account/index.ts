import { createHandler } from "./handler.ts";
import { appleConfiguration } from "../_shared/apple-credentials.ts";

Deno.serve(createHandler({
  url: Deno.env.get("SUPABASE_URL") ?? "",
  publicKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  apple: appleConfiguration(name => Deno.env.get(name)),
}));
