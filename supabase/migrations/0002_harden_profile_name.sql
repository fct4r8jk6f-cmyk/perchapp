-- ============================================================================
-- 0002 — Harden profiles.name against HTML injection (defence-in-depth)
-- ============================================================================
-- The app escapes every dynamic string before it hits innerHTML (the esc()
-- invariant), so this is NOT the primary XSS defence — rendering is. But the
-- profiles.name column in 0001 validated length only (1–30 chars), accepting
-- any text including '<img src=x onerror=...>'. This adds a belt-and-braces
-- check at the data layer so a malformed name can never even be stored.
--
-- Scope is deliberately narrow: block ONLY the angle brackets that open an HTML
-- tag. Apostrophes (O'Brien), accents (Marie-Ève, José), hyphens and spaces are
-- all legitimate first names in an en/fr-CA app and stay allowed. Escaping still
-- handles & " ' at render time.
--
-- Idempotent: safe to run on the already-live DB (adds the constraint if missing)
-- and on a fresh setup after 0001 (skips if it somehow already exists).
--
-- NOTE: ADD CONSTRAINT validates existing rows. If any current profile name
-- contains '<' or '>', this will error — clean that row first, then re-run.
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_name_no_html'
  ) then
    alter table public.profiles
      add constraint profiles_name_no_html check (name !~ '[<>]');
  end if;
end $$;
