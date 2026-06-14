// ============================================================================
// Perch backend config — TEMPLATE
// ----------------------------------------------------------------------------
// 1. Copy this file to  config.js   (config.js is gitignored — never commit keys)
// 2. Fill in your Supabase project's URL + anon (public) key
//    Supabase dashboard -> Project Settings -> API
//
// The "anon" key is the PUBLIC key and is safe to ship in a frontend — Row-Level
// Security (in supabase/migrations/0001_init.sql) is what protects your data.
// NEVER put the "service_role" key here; it bypasses RLS.
// ============================================================================
window.PERCH_CONFIG = {
  url: "https://YOUR-PROJECT-ref.supabase.co",
  anonKey: "YOUR-ANON-PUBLIC-KEY",
};
