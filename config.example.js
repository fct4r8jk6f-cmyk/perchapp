// ============================================================================
// Perch backend config — TEMPLATE
// ----------------------------------------------------------------------------
// 1. Copy this file to  config.js   and fill in your keys.
// 2. Fill in your Supabase project's URL + anon (public) key
//    Supabase dashboard -> Project Settings -> API
//
// The "anon" key is the PUBLIC key and is safe to ship in a frontend — Row-Level
// Security (in supabase/migrations/0001_init.sql) is what protects your data.
// Committing config.js is therefore fine (this repo does), BUT only because it
// holds just that public key. NEVER put the "service_role" key in either file;
// it bypasses RLS and must never be committed or shipped to the client.
// ============================================================================
window.PERCH_CONFIG = {
  url: "https://YOUR-PROJECT-ref.supabase.co",
  anonKey: "YOUR-ANON-PUBLIC-KEY",
};
