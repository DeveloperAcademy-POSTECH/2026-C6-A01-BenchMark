import { createStoryModerationHandler, withEducationBrowserAccess } from "./handler.ts";

Deno.serve(withEducationBrowserAccess(createStoryModerationHandler({
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  openaiKey: Deno.env.get("OPENAI_API_KEY") ?? "",
  model: Deno.env.get("OPENAI_STORY_MODERATION_MODEL") || undefined,
})));
