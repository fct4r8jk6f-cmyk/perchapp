-- ============================================================================
-- Perch — Production PostgreSQL schema (schema.sql)
-- ============================================================================
--
-- SCOPE
-- -----
-- This is the real backend that the single-file Perch demo (index.html) implies.
-- Perch forms small groups (4-8 people) around real-world Montreal activities so
-- strangers become friends. The demo holds everything in one in-memory `state`
-- object; this schema is the durable, multi-user, server-authoritative model
-- behind it. It covers: accounts + on-demand profiles, the personality quiz and
-- 12 archetypes, the activity/venue/group/occurrence catalog, the single join
-- funnel (cap -> profile gate -> reservation -> finish), waitlist + automatic
-- backfill, attendance-based reliability, friendships/DMs/group chat, safety
-- (blocks/reports/take-a-break), notifications, settings, the Perch+
-- subscription, and the Quebec Law 25 / PIPEDA / Bill 96 compliance surface
-- (consent, versioned bilingual legal docs, export/deletion, audit).
--
-- It is intentionally a schema, not an app: invariants the demo enforces in JS
-- (cap counting, the join path, reliability derivation, pay-at-venue) are encoded
-- here as columns, constraints, indexes, and comments so the application layer can
-- enforce them cheaply and consistently. Time-based behaviour (90s backfill TTL,
-- weekly reset, 3h reminders, 24h moderation SLA) lives in jobs; the rows those
-- jobs read/write are modelled here.
--
-- CANONICAL-ENGLISH + TRANSLATIONS DECISION  (Bill 96 / Law 25 context)
-- ---------------------------------------------------------------------
-- Reference/seed data (activities, interests, archetypes, quiz questions/options,
-- activity badges, category labels, group templates) is stored CANONICAL ENGLISH
-- and matched/filtered/indexed on the English value, mirroring the demo (search
-- and filters run against canonical English; *_FR dicts apply only at render).
--
-- Translations are stored in a SINGLE GENERIC `translations` table keyed by
-- (entity_type, entity_key, field, locale) rather than per-locale columns. Chosen
-- because:
--   * Bill 96 makes French first-class, not an afterthought, and Perch may add
--     locales (e.g. plain en-CA) — a generic table scales to N locales/fields
--     without DDL churn or a wide, mostly-null table.
--   * It lets ops add an FR string for a new activity/interest/badge as plain
--     DATA (one INSERT), matching the demo rule "adding an activity means adding
--     its ACTFR entry" — no migration to ship a translation.
--   * Translation completeness (Bill 96 parity, Law 25 equal-quality legal docs)
--     becomes a single auditable query: rows present per (entity, field, locale).
-- The trade-off (no per-column FK/NOT NULL on a specific translation) is accepted;
-- parity is enforced by the application + a parity report, exactly as the demo's
-- `check-i18n` skill does. USER-GENERATED content (names, usernames, bios, chat,
-- venue proper nouns) is NEVER translated — stored as-is.
--
-- Legal documents are the ONE exception: because each (doc, locale) version is a
-- large immutable blob that must be independently versioned and consented-to, they
-- live in their own `legal_documents` table (one row per doc+locale+version), not
-- in the generic `translations` table.
--
-- CONVENTIONS
-- -----------
--   * snake_case identifiers; UUID PKs default gen_random_uuid() (pgcrypto).
--   * created_at/updated_at timestamptz on mutable tables; updated_at maintained
--     by a shared trigger (defined once, attached per table).
--   * Reference catalog rows (activities, interests, archetypes) use their stable
--     business id/key as PK (text), matching the demo's English-canonical keys, so
--     translations and FKs join on the human-readable key.
--   * Money is numeric(8,2). NOTE: Perch captures NO card data anywhere — `price`
--     columns are display/pay-at-venue amounts only (see reservations).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive username/email

-- Shared updated_at trigger ---------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ENUM TYPES  (every fixed set the product defines)
-- ============================================================================

-- The 12 personality archetypes (ARCH ~index.html:1106). Stored as enum so a
-- profile/group-mix can never reference an unknown type.
CREATE TYPE archetype_key AS ENUM (
  'spark','connector','explorer','easygoer','anchor','observer',
  'curator','grounding','wildcard','storyteller','navigator','wavelength'
);

-- Activity catalog categories (the browse rail). 'For you' is a virtual,
-- personalized rail in the UI rather than a stored category on rows, but it is a
-- legal category value the client filters by, so it is included.
CREATE TYPE activity_category AS ENUM (
  'For you','Food & Drink','Outdoors','Arts & Culture',
  'Games','Chill','Active','Evening Out'
);

-- A user's standing in a group / join lifecycle. Only 'active' (confirmed) joins
-- count toward the weekly cap; 'waitlisted' does NOT.
CREATE TYPE rsvp_status AS ENUM ('active','waitlisted','left','attended','cancelled');

-- Group lifecycle. 'forming' accepts joins; 'full' opens the waitlist; 'today'
-- and 'week' are UI windows; 'cancelled' by host/system.
CREATE TYPE group_status AS ENUM ('forming','today','week','full','cancelled');

-- Day-of coordination status, event-day only. 'here' is what triggers check-in.
-- 'ride' is display-only (splitting a ride; no carpool matching).
CREATE TYPE day_of_status AS ENUM ('on_my_way','running_late','here','ride');

-- Backfill offer lifecycle. A spot opening fires a 90s offer to the next person.
CREATE TYPE backfill_offer_status AS ENUM ('active','claimed','expired');

-- Waitlist entry lifecycle.
CREATE TYPE waitlist_status AS ENUM ('waiting','offered','claimed','expired','left');

-- Moderation case lifecycle. Human review within 24h SLA.
CREATE TYPE report_status AS ENUM ('submitted','under_review','actioned','dismissed');

-- The 6 report reasons (REASONS const, bilingual).
CREATE TYPE report_reason AS ENUM (
  'inappropriate_messages','harassment','made_uncomfortable',
  'spam_scam','no_show_unsafe','other'
);

-- Plan tier drives the weekly join cap: free = 2/week, plus = 5/week.
CREATE TYPE subscription_tier AS ENUM ('free','plus');

-- Perch+ subscription lifecycle.
CREATE TYPE subscription_status AS ENUM ('trial','active','cancelled','expired');
CREATE TYPE subscription_plan   AS ENUM ('monthly','annual');

-- Notification categories (gateable by per-type settings).
CREATE TYPE notification_type AS ENUM (
  'hang_reminder','message','friend_request','group_match',
  'product_update','backfill_offer','checkin','moderation_outcome'
);

-- Phone verification lifecycle. OPTIONAL — never blocks join/host.
CREATE TYPE verification_status AS ENUM ('pending','verified','failed');

-- Kinds of consent captured (Law 25 / PIPEDA point-in-time records).
CREATE TYPE consent_kind AS ENUM (
  'age_18_plus','terms','privacy','guidelines','moderation','wellbeing','marketing'
);

-- The 5 in-app legal docs.
CREATE TYPE legal_doc_key AS ENUM ('terms','privacy','guidelines','moderation','wellbeing');

-- Supported locales. Bill 96: fr-CA is first-class. Used by translations + legal.
CREATE TYPE locale AS ENUM ('en','fr-CA');

-- Chat message kind (group chat / DM). System messages have null sender.
CREATE TYPE message_kind AS ENUM ('user','system');

-- Friend request lifecycle.
CREATE TYPE friend_request_status AS ENUM ('pending','accepted','declined');

-- Group membership role.
CREATE TYPE membership_role AS ENUM ('member','host');

-- Privacy gates (who can message / who can add).
CREATE TYPE who_can AS ENUM ('everyone','friends','friends_of_friends','no_one');

-- Theme + text size + locale preference enums.
CREATE TYPE theme_pref AS ENUM ('light','dark','system');
CREATE TYPE text_size  AS ENUM ('default','large');

-- Data subject request (Law 25) lifecycle.
CREATE TYPE dsr_status AS ENUM ('requested','processing','completed','failed','cancelled');

-- ============================================================================
-- REFERENCE / CATALOG DATA  (canonical English; translated via `translations`)
-- ============================================================================

-- Archetypes (the 12). Canonical English copy lives here; ARFR equivalents go in
-- `translations` (entity_type='archetype'). `compat` is the 2 keys this type vibes
-- with (used by group-fit explainers); kept as an array of the enum.
CREATE TABLE archetypes (
  key          archetype_key PRIMARY KEY,
  emoji        text          NOT NULL,
  name         text          NOT NULL,             -- "The Spark"
  tag          text          NOT NULL,             -- one-line tagline
  traits       text[]        NOT NULL,             -- 3 descriptors
  bring        text[]        NOT NULL,             -- 3 group benefits
  loves        text[]        NOT NULL,             -- 3 sample activities
  descr        text[]        NOT NULL,             -- 3 character descriptors
  compat       archetype_key[] NOT NULL,           -- 2 compatible archetypes
  population_pct numeric(5,2),                      -- e.g. 11.00 (% of population)
  gradient_class text        NOT NULL,             -- CSS class e.g. 'g-spark'
  dot_color    text                                -- hex e.g. '#FF7A5C'
);
COMMENT ON TABLE archetypes IS
  'The 12 personality archetypes. Canonical English; ARFR strings go in translations. Matched on key (storage key, never translated).';

-- Personality quiz (7 questions). Canonical English; QFR in translations.
CREATE TABLE quiz_questions (
  id        smallint PRIMARY KEY CHECK (id BETWEEN 0 AND 6),  -- 7 questions, 0..6
  prompt    text     NOT NULL
);
COMMENT ON TABLE quiz_questions IS '7-question personality quiz (QUESTIONS ~index.html:1159). Runs BEFORE sign-in (anonymous, shareable acquisition artifact).';

CREATE TABLE quiz_options (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id     smallint NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
  option_index    smallint NOT NULL CHECK (option_index BETWEEN 0 AND 3),  -- up to 4 options
  emoji           text     NOT NULL,
  label           text     NOT NULL,                          -- canonical English
  archetype_weights archetype_key[] NOT NULL,                 -- 1-3 keys this option scores
  UNIQUE (question_id, option_index)
);
COMMENT ON COLUMN quiz_options.archetype_weights IS 'Keys that gain a point if this option is chosen; the top tally across 7 answers becomes profile_key.';

-- Interests (12, canonical English). INT_FR in translations.
CREATE TABLE interests (
  key        text PRIMARY KEY,                  -- canonical English, e.g. 'Board games'
  sort_order smallint
);
COMMENT ON TABLE interests IS '12 canonical-English interests (INTERESTS ~index.html:1729). Display label translated via translations(entity_type=''interest'').';

-- Venues (proper nouns — NEVER translated; venue names don't translate).
CREATE TABLE venues (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,                  -- "Pub Saint-Laurent" (proper noun)
  address       text,
  neighbourhood text,                           -- Montreal neighbourhood
  lat           double precision,
  lng           double precision,
  is_verified   boolean NOT NULL DEFAULT false, -- confirmed by the team
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_venues_updated BEFORE UPDATE ON venues
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
COMMENT ON TABLE venues IS 'Venues are proper nouns and are NOT translated (only descriptive group/activity names translate).';

-- Activity templates (~22). Canonical English; name/vibe/planb/badge -> ACTFR/
-- BADGE_FR in translations. `price` present => ticketed (pay-at-venue).
CREATE TABLE activities (
  id            text PRIMARY KEY,               -- 'thursdays','trivia',... (demo ids)
  icon          text NOT NULL,                  -- emoji
  name          text NOT NULL,                  -- canonical English
  category      activity_category NOT NULL,
  default_venue_id uuid REFERENCES venues(id) ON DELETE SET NULL,
  schedule_text text,                           -- 'Wed · 7:30 PM' (human-readable)
  group_size_text text,                         -- '4-6 people'
  min_size      smallint CHECK (min_size >= 1),
  max_size      smallint CHECK (max_size >= min_size),
  vibe          text,                           -- canonical English prose
  plan_b        text,                           -- canonical English prose
  social_proof  text,                           -- '26 joined this week' (display)
  badge         text,                           -- '🔥 Popular' etc; BADGE_FR in translations
  -- Ticketed iff price IS NOT NULL. Amount is paid AT THE VENUE. See reservations:
  -- Perch captures NO card and stores NO payment instrument anywhere.
  price         numeric(8,2) CHECK (price IS NULL OR price >= 0),
  is_recurring  boolean NOT NULL DEFAULT true,
  is_active     boolean NOT NULL DEFAULT true,  -- soft-retire from catalog
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_activities_updated BEFORE UPDATE ON activities
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_activities_category ON activities(category) WHERE is_active;  -- browse-by-category hot path
COMMENT ON COLUMN activities.price IS 'Presence => ticketed activity. PAY-AT-VENUE only: NO card is captured, NO payment instrument is stored. The code on the reservation is what the user shows at the door.';

-- Activity occurrences (a specific dated instance of a recurring activity). Groups
-- form against an occurrence.
CREATE TABLE activity_occurrences (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id   text NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  venue_id      uuid REFERENCES venues(id) ON DELETE SET NULL,
  starts_at     timestamptz NOT NULL,           -- date+time of this occurrence
  groups_forming smallint NOT NULL DEFAULT 0,
  status        group_status NOT NULL DEFAULT 'forming',  -- reuse window enum loosely
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_occurrences_updated BEFORE UPDATE ON activity_occurrences
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_occurrences_activity_time ON activity_occurrences(activity_id, starts_at);
CREATE INDEX idx_occurrences_upcoming ON activity_occurrences(starts_at) WHERE starts_at > now();

-- ============================================================================
-- IDENTITY: accounts, profiles, quiz responses, settings, subscription
-- ============================================================================

-- The account. Created at sign-in (after the anonymous quiz + age gate + terms).
-- Profile is NOT here — it is created on-demand at first join/host (see profiles).
--
-- RELIABILITY (attended/checked_in): reliability is DERIVED, not a stored public
-- score: is_reliable := (attended > 0 OR checked_in). There is intentionally no
-- numeric "show-up rate" persisted for others to see — "not a popularity contest".
-- `attended` is bumped ONLY on check-in (the 'here' day-of status), never on join.
CREATE TABLE accounts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email           citext UNIQUE,                 -- via Apple/Google/email; case-insensitive
  phone           text,                          -- optional; for OPTIONAL verification only
  age             smallint NOT NULL CHECK (age >= 18),  -- 18+ self-attested age gate
  age_attested_at timestamptz,                   -- locked once set (regulatory)
  signed_in       boolean NOT NULL DEFAULT false,
  agreed          boolean NOT NULL DEFAULT false,-- accepted terms/privacy/guidelines before first join
  verified        boolean NOT NULL DEFAULT false,-- OPTIONAL phone verification; NEVER blocks join/host
  verified_at     timestamptz,
  -- Reliability inputs (NOT a public score):
  attended        integer NOT NULL DEFAULT 0 CHECK (attended >= 0),  -- bumped only on check-in
  checked_in      boolean NOT NULL DEFAULT false,
  subscription_tier subscription_tier NOT NULL DEFAULT 'free',       -- denormalized for cheap cap checks
  preferred_locale locale NOT NULL DEFAULT 'fr-CA',                  -- Bill 96: default French in QC
  region          text,                          -- e.g. 'QC' (drives Bill 96 default)
  -- Account state machine flags:
  break_until     timestamptz,                   -- take-a-break: paused while > now()
  deleted_at      timestamptz,                   -- soft-delete (Law 25); PII scrubbed, id retained
  email_hash      text,                          -- SHA-256 of email, kept after deletion for re-reg block
  phone_hash      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_accounts_updated BEFORE UPDATE ON accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
COMMENT ON COLUMN accounts.attended IS 'Count of check-ins. Bumped ONLY by check-in (day-of ''here''), never by joining. Drives derived reliability.';
COMMENT ON COLUMN accounts.verified IS 'OPTIONAL phone verification flag. Must NEVER gate joining or hosting — trust signal only.';
COMMENT ON COLUMN accounts.break_until IS 'Take-a-break (7/14/30d). While > now(): no joins, no matches, notifications suppressed. Auto-clears when past.';
COMMENT ON COLUMN accounts.deleted_at IS 'Law 25 deletion: PII scrubbed in app/jobs; row retained (id, *_hash, deleted_at) for dispute/re-reg block only.';

-- On-demand profile (1:1 with account). Created at FIRST join/host, not at signup.
-- Browsing is free without a profile. profile_complete gates the first join/host.
CREATE TABLE profiles (
  account_id      uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  name            text NOT NULL CHECK (char_length(name) <= 30),   -- first name only
  -- Username: case-insensitive unique, 3-20 chars, [a-z0-9._]; also blocked vs
  -- RESERVED_NAMES (see reserved_usernames seed). citext gives the unique check.
  username        citext NOT NULL,
  emoji           text NOT NULL,                  -- single-emoji avatar (PROFILE_EMOJIS)
  bio             text CHECK (bio IS NULL OR char_length(bio) <= 120),
  photo_url       text,                           -- friends-only visibility (enforce at API)
  profile_key     archetype_key REFERENCES archetypes(key) ON DELETE SET NULL,  -- quiz result
  profile_complete boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT username_format CHECK (
    char_length(username) BETWEEN 3 AND 20
    AND username::text ~ '^[a-z0-9._]+$'
  )
);
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
-- Case-insensitive uniqueness (citext already case-folds; explicit unique index):
CREATE UNIQUE INDEX uq_profiles_username ON profiles (username);
COMMENT ON TABLE profiles IS 'Created ON DEMAND at first join/host (openProfileSetup). profile_complete gates first join/host; browsing is free without it.';
COMMENT ON COLUMN profiles.photo_url IS 'Friends-only. API must withhold photo/bio/interests from non-friends — pre-friendship visibility = first name + emoji + archetype badge only.';

-- Reserved usernames (RESERVED_NAMES) — seeded so username validation can check
-- the directory AND reserved words server-side, exactly like usernameStatus().
CREATE TABLE reserved_usernames (
  username citext PRIMARY KEY
);
COMMENT ON TABLE reserved_usernames IS 'RESERVED_NAMES. Username availability check = NOT taken in profiles AND NOT present here.';

-- User <-> Interest (1-5 per user; canonical English keys).
CREATE TABLE user_interests (
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  interest_key text NOT NULL REFERENCES interests(key) ON DELETE CASCADE,
  added_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, interest_key)
);
COMMENT ON TABLE user_interests IS 'Junction: 1-5 interests per user. Stored as canonical English keys; labels translated at render (INT_FR).';

-- Quiz responses. The quiz is anonymous pre-auth; on profile creation the result
-- is attached here. answers = 7-slot array of chosen option indices (0..3).
CREATE TABLE quiz_responses (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid REFERENCES accounts(id) ON DELETE CASCADE,  -- null while anonymous
  anonymous_session_id uuid,                      -- ties pre-auth quiz to eventual account
  answers       smallint[] NOT NULL CHECK (array_length(answers,1) = 7),
  result_archetype archetype_key NOT NULL REFERENCES archetypes(key) ON DELETE RESTRICT,
  retaken_count smallint NOT NULL DEFAULT 0,      -- Perch+ seasonal re-match
  responded_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_quiz_responses_account ON quiz_responses(account_id);
CREATE INDEX idx_quiz_responses_anon ON quiz_responses(anonymous_session_id);
COMMENT ON TABLE quiz_responses IS 'Anonymous quiz (pre-auth) keyed by anonymous_session_id; merged to account_id on profile creation. answers[i] = option index for question i.';

-- Per-user settings (1:1). Server-synced. Theme is in-session in the demo but
-- modelled here for multi-device. Accessibility settings are FUNCTIONAL.
CREATE TABLE user_settings (
  account_id     uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  who_message    who_can NOT NULL DEFAULT 'friends',
  who_add        who_can NOT NULL DEFAULT 'everyone',
  active_status  boolean NOT NULL DEFAULT true,   -- show online status
  theme          theme_pref NOT NULL DEFAULT 'system',
  reduce_motion  boolean NOT NULL DEFAULT false,
  bold_text      boolean NOT NULL DEFAULT false,
  high_contrast  boolean NOT NULL DEFAULT false,
  larger_targets boolean NOT NULL DEFAULT false,  -- min 48px hit areas
  text_size      text_size NOT NULL DEFAULT 'default',
  notif_reminders boolean NOT NULL DEFAULT true,  -- hang reminders ~3h before
  notif_messages  boolean NOT NULL DEFAULT true,
  notif_friend_req boolean NOT NULL DEFAULT true,
  notif_matches   boolean NOT NULL DEFAULT true,
  notif_updates   boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_settings_updated BEFORE UPDATE ON user_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
COMMENT ON TABLE user_settings IS 'who_message/who_add are server-ENFORCED access control. Accessibility flags are functional (applied as CSS attrs). notif_* gate delivery per type.';

-- Perch+ subscription (1 active per account). tier on accounts is denormalized
-- from here for cheap cap checks; keep them consistent in the app layer.
-- NOTE: No card/payment instrument is stored — billing is delegated to the app
-- store (Apple/Google) or processor; only lifecycle + amount-for-display here.
CREATE TABLE subscriptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  status        subscription_status NOT NULL,
  plan          subscription_plan NOT NULL,
  amount        numeric(8,2) NOT NULL,            -- 4.99/mo or 39/yr (display)
  started_at    timestamptz,
  trial_ends_at timestamptz,                      -- 7-day free trial
  renews_at     timestamptz,
  cancels_at    timestamptz,
  auto_renew    boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_subscriptions_updated BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
-- One active/trial subscription per account at a time:
CREATE UNIQUE INDEX uq_active_subscription ON subscriptions(account_id)
  WHERE status IN ('trial','active');
COMMENT ON TABLE subscriptions IS 'Perch+ (free->plus raises weekly cap 2->5, priority matching, host perks). NO card data stored here — billing via app store/processor.';

-- Phone verification attempts (OPTIONAL; never blocks anything).
CREATE TABLE phone_verifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  phone         text NOT NULL,                    -- E.164
  code          text NOT NULL,                    -- 4-digit (store hashed in prod)
  code_sent_at  timestamptz NOT NULL DEFAULT now(),
  code_expires_at timestamptz NOT NULL,           -- ~15 min window
  verified_at   timestamptz,
  status        verification_status NOT NULL DEFAULT 'pending',
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_phone_verif_account ON phone_verifications(account_id);
COMMENT ON TABLE phone_verifications IS 'OPTIONAL verification (openVerify). Setting accounts.verified=true is a trust signal; it must NEVER appear in any join/host gate.';

-- ============================================================================
-- GROUPS, MEMBERSHIP, JOINS (the single funnel), RESERVATIONS
-- ============================================================================

-- A small group (4-8) around an activity occurrence. host_account_id null =
-- system-generated. filled <= max_size is enforced; when filled = max_size the
-- group is full and the waitlist opens (open_waitlist).
CREATE TABLE groups (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurrence_id uuid REFERENCES activity_occurrences(id) ON DELETE SET NULL,
  activity_id   text REFERENCES activities(id) ON DELETE SET NULL,  -- denormalized for fast browse
  host_account_id uuid REFERENCES accounts(id) ON DELETE SET NULL, -- null = system group
  emoji         text NOT NULL,
  name          text NOT NULL,                    -- descriptive (translatable via GRPFR)
  when_text     text,                             -- 'Today · 7:00 PM' (display)
  starts_at     timestamptz,                      -- canonical event time (for reminders/day-of)
  min_size      smallint NOT NULL DEFAULT 4 CHECK (min_size >= 2),
  max_size      smallint NOT NULL CHECK (max_size BETWEEN min_size AND 10),  -- Perch+ host up to 10
  filled        smallint NOT NULL DEFAULT 0 CHECK (filled >= 0),
  vibe_tags     text[],                           -- translatable
  archetype_mix archetype_key[],                  -- composition (matching)
  personality   text,                             -- group dynamic prose (GRPFR)
  compatibility text,                             -- "2 people with your vibe..." (GRPFR)
  status        group_status NOT NULL DEFAULT 'forming',
  open_waitlist boolean NOT NULL DEFAULT false,   -- true once full and accepting waitlist
  is_recommended boolean NOT NULL DEFAULT false,  -- 'Picked for you'
  day_sim_seeded boolean NOT NULL DEFAULT false,  -- seedDaySim ran once for this event
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT filled_within_capacity CHECK (filled <= max_size)  -- invariant: never oversubscribe
);
CREATE TRIGGER trg_groups_updated BEFORE UPDATE ON groups
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_groups_occurrence ON groups(occurrence_id);
CREATE INDEX idx_groups_activity ON groups(activity_id);
CREATE INDEX idx_groups_open ON groups(status) WHERE status = 'forming';  -- matching: find joinable groups
CREATE INDEX idx_groups_starts_at ON groups(starts_at);                   -- reminder job window scan
COMMENT ON CONSTRAINT filled_within_capacity ON groups IS 'Group can never exceed capacity (filled <= max_size). Reaching max opens the waitlist.';

-- Group membership / the join record. THIS is the join ledger the weekly cap
-- counts. A user has at most ONE non-terminal membership per group.
--
-- WEEKLY CAP (server-side, ISO week):
--   Free tier = 2 confirmed joins/ISO-week (Mon-Sun); the 3rd hits the Perch+
--   paywall. Perch+ = 5/week. Enforced in requestJoin() BEFORE the profile gate
--   and BEFORE any reservation. The cap counts CONFIRMED joins (status='active'
--   or attended) within the current ISO week; waitlist entries do NOT count.
--   `join_iso_week` is a GENERATED column (the ISO year-week of joined_at) so the
--   count is a cheap index lookup: COUNT(*) WHERE account_id=? AND join_iso_week=?
--   AND status IN ('active','attended'). See idx_memberships_cap below.
CREATE TABLE group_memberships (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  activity_id   text REFERENCES activities(id) ON DELETE SET NULL,  -- activity chosen at join (may differ from group default)
  role          membership_role NOT NULL DEFAULT 'member',
  status        rsvp_status NOT NULL DEFAULT 'active',
  attended      boolean NOT NULL DEFAULT false,   -- true when this member checks in on day-of
  joined_at     timestamptz NOT NULL DEFAULT now(),
  left_at       timestamptz,
  -- ISO week (e.g. '2026-24') of the join, for cheap weekly-cap counting.
  -- Anchored to America/Toronto (Perch's Montreal market) so the week boundary is
  -- local-Monday; pinning the zone also makes to_char IMMUTABLE, which a STORED
  -- generated column requires (a bare to_char(timestamptz,...) is only STABLE and
  -- would be rejected because it depends on the session TimeZone).
  join_iso_week text GENERATED ALWAYS AS
    (to_char(timezone('America/Toronto', joined_at), 'IYYY-IW')) STORED,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_memberships_updated BEFORE UPDATE ON group_memberships
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
-- One active membership per (user, group): a user can't double-join a group.
CREATE UNIQUE INDEX uq_one_active_membership ON group_memberships(group_id, account_id)
  WHERE status IN ('active','attended');
-- Group roster lookup (who is in this group, active first):
CREATE INDEX idx_memberships_group ON group_memberships(group_id, status);
-- A user's joined groups (Joined screen, "my groups"):
CREATE INDEX idx_memberships_account ON group_memberships(account_id, status);
-- WEEKLY CAP COUNT hot path — count confirmed joins in the current ISO week:
CREATE INDEX idx_memberships_cap ON group_memberships(account_id, join_iso_week)
  WHERE status IN ('active','attended');
COMMENT ON COLUMN group_memberships.join_iso_week IS 'Generated ISO year-week of joined_at. Weekly cap = COUNT(*) WHERE account_id=? AND join_iso_week=? AND status IN (active,attended). Free=2, Plus=5. Waitlist excluded.';
COMMENT ON TABLE group_memberships IS 'The join ledger. ALL joins (incl. waitlist claims) funnel through requestJoin -> cap -> profile gate -> reservation(if ticketed) -> this row. attended flips on check-in.';

-- Reservation — one per ticketed (and recorded per any) join. Holds the human
-- code shown AT THE VENUE. PAY-AT-VENUE: NO card, NO payment instrument, NO charge
-- is stored anywhere. `price` is the display/at-venue amount only.
CREATE TABLE reservations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  membership_id uuid NOT NULL UNIQUE REFERENCES group_memberships(id) ON DELETE CASCADE,
  code          text NOT NULL,                    -- 'PCH-XXXX' (resvCode); shown at venue
  ticket        boolean NOT NULL DEFAULT false,   -- true if activity has a price
  price         numeric(8,2) CHECK (price IS NULL OR price >= 0),  -- pay-at-venue amount; null if free
  voided_at     timestamptz,                      -- set if the join is cancelled (prevents double pay)
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT resv_code_format CHECK (code ~ '^PCH-[A-Z0-9]{4}$')
);
CREATE UNIQUE INDEX uq_reservation_code ON reservations(code);
COMMENT ON TABLE reservations IS 'Pay-at-venue ticket record. NO card captured, NO payment row exists — the PCH-XXXX code is presented at the door (honours the no-payments constraint). Every join gets a code; ticket/price only set for priced activities.';
COMMENT ON COLUMN reservations.code IS 'resvCode(): PCH- + 4 unambiguous alphanumerics. Unique. Human-readable check-in token verified offline at venue.';

-- ============================================================================
-- WAITLIST + AUTOMATIC BACKFILL
-- ============================================================================

-- Waitlist entry — one active per (user, group occurrence). position is
-- DETERMINISTIC and NEVER #1 (wlPosition: base 2-4, reliable members one slot
-- higher, min 2 — you're never the only one waiting).
CREATE TABLE waitlist_entries (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  activity_id   text REFERENCES activities(id) ON DELETE SET NULL,
  position      smallint NOT NULL CHECK (position >= 2),  -- never #1
  status        waitlist_status NOT NULL DEFAULT 'waiting',
  entered_at    timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_waitlist_updated BEFORE UPDATE ON waitlist_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
-- One active waitlist entry per (user, group):
CREATE UNIQUE INDEX uq_one_active_waitlist ON waitlist_entries(group_id, account_id)
  WHERE status IN ('waiting','offered');
-- Next-in-line lookup when a spot opens (FIFO by position then entered_at):
CREATE INDEX idx_waitlist_queue ON waitlist_entries(group_id, position, entered_at)
  WHERE status = 'waiting';
-- A user's waitlisted groups:
CREATE INDEX idx_waitlist_account ON waitlist_entries(account_id, status);
COMMENT ON COLUMN waitlist_entries.position IS 'Deterministic, never #1 (CHECK >= 2). Reliable members rank one slot higher. Snapshot at queue time; recompute on reliability change if reranking.';

-- Backfill offer — fired to the next waitlisted person when a spot opens. 90s TTL.
-- A claim routes back through requestJoin (re-applying cap/profile/reservation).
CREATE TABLE backfill_offers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  waitlist_entry_id uuid NOT NULL REFERENCES waitlist_entries(id) ON DELETE CASCADE,
  group_id        uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  account_id      uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  offered_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,           -- offered_at + 90s
  status          backfill_offer_status NOT NULL DEFAULT 'active',
  claimed_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
-- Only one active offer per group at a time (FIFO: never pop multiple in parallel):
CREATE UNIQUE INDEX uq_one_active_offer_per_group ON backfill_offers(group_id)
  WHERE status = 'active';
-- Expiry sweep job hot path (find offers past TTL):
CREATE INDEX idx_backfill_expiry ON backfill_offers(expires_at) WHERE status = 'active';
CREATE INDEX idx_backfill_account ON backfill_offers(account_id) WHERE status = 'active';
COMMENT ON TABLE backfill_offers IS 'Time-limited (90s) offer when a full group frees a spot. Claim -> requestJoin (cap/profile/reservation re-applied). Expiry job sweeps status=active WHERE expires_at < now(); user stays waitlisted on expiry.';

-- ============================================================================
-- ATTENDANCE / DAY-OF COORDINATION
-- ============================================================================

-- Day-of status per (user, group). Only meaningful on event day. 'here' routes
-- through check-in. 'ride' is display-only.
CREATE TABLE day_of_statuses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  status      day_of_status NOT NULL,
  want_ride   boolean NOT NULL DEFAULT false,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, account_id)
);
CREATE TRIGGER trg_dayof_updated BEFORE UPDATE ON day_of_statuses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
COMMENT ON TABLE day_of_statuses IS 'Event-day coordination only. Setting ''here'' routes through check-in (the shared path). Visible only to group members on event day.';

-- Check-in ledger — idempotent per (user, group). Writing a check-in is what
-- bumps accounts.attended (reliability), flips group_memberships.attended, and
-- posts the "X checked in" system message.
CREATE TABLE check_ins (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  checked_in_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, account_id)                   -- idempotent: one check-in per member per event
);
CREATE INDEX idx_checkins_account ON check_ins(account_id);
COMMENT ON TABLE check_ins IS 'The single check-in path (checkIn). Idempotent per (group,user). First-ever check-in bumps accounts.attended -> derived reliability. Attendance-based reliability lives here, not in a score.';

-- ============================================================================
-- SOCIAL: friendships, requests, DMs, group chat, past connections
-- ============================================================================

-- Friendships (symmetric). Stored once with an ordered pair (low,high) so the
-- unique constraint dedupes A-B / B-A.
CREATE TABLE friendships (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_lo    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  account_hi    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  context       text,                             -- where they met, e.g. 'Trivia Night'
  established_at timestamptz NOT NULL DEFAULT now(),
  CHECK (account_lo < account_hi),                -- canonical ordering => one row per pair
  UNIQUE (account_lo, account_hi)
);
CREATE INDEX idx_friendships_lo ON friendships(account_lo);
CREATE INDEX idx_friendships_hi ON friendships(account_hi);
COMMENT ON TABLE friendships IS 'Symmetric friendship stored once (account_lo<account_hi). Friendship unlocks friends-only photo/bio/interests (pre-friendship = first name + emoji only).';

-- Friend requests (directional).
CREATE TABLE friend_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id     uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  recipient_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  status        friend_request_status NOT NULL DEFAULT 'pending',
  context       text,                             -- where they met (null if from discover)
  sent_at       timestamptz NOT NULL DEFAULT now(),
  responded_at  timestamptz,
  CHECK (sender_id <> recipient_id)
);
-- One pending request per direction:
CREATE UNIQUE INDEX uq_pending_request ON friend_requests(sender_id, recipient_id)
  WHERE status = 'pending';
CREATE INDEX idx_requests_recipient ON friend_requests(recipient_id, status);  -- incoming list
CREATE INDEX idx_requests_sender ON friend_requests(sender_id, status);        -- sent list
COMMENT ON TABLE friend_requests IS 'who_add (settings) gates creation server-side: reject if recipient set no_one, or friends_of_friends and not a FoF.';

-- Past connections (MET_SEED): people you've met at activities.
CREATE TABLE past_connections (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_lo    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  account_hi    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  met_context   text,                             -- 'Trivia Night · Pub Saint-Laurent'
  met_on        date,
  verified      boolean NOT NULL DEFAULT false,   -- both confirmed the connection
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (account_lo < account_hi),
  UNIQUE (account_lo, account_hi, met_context)
);
COMMENT ON TABLE past_connections IS 'Met-at-activity history (MET_SEED). Feeds the friends/discover surfaces and mutual counts. met_context embeds activity+venue; prose translated via frActText at render.';

-- Direct message threads (1:1 between friends).
CREATE TABLE dm_threads (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_lo    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  account_hi    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_message_at timestamptz,
  CHECK (account_lo < account_hi),
  UNIQUE (account_lo, account_hi)
);
CREATE INDEX idx_dm_threads_lo ON dm_threads(account_lo, last_message_at DESC);
CREATE INDEX idx_dm_threads_hi ON dm_threads(account_hi, last_message_at DESC);

CREATE TABLE direct_messages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id     uuid NOT NULL REFERENCES dm_threads(id) ON DELETE CASCADE,
  sender_id     uuid REFERENCES accounts(id) ON DELETE SET NULL,  -- null when sender deleted (anonymized)
  body          text NOT NULL,
  sent_at       timestamptz NOT NULL DEFAULT now(),
  seen_at       timestamptz                       -- null until read
);
CREATE INDEX idx_dm_thread_time ON direct_messages(thread_id, sent_at);
COMMENT ON TABLE direct_messages IS 'who_message (settings) gates send server-side; blocks reject sends silently. On account deletion sender_id is nulled (anonymized), body retained or scrubbed per Law 25 policy.';

-- Group chat thread (1:1 with group) + messages. First-names-only at render.
CREATE TABLE group_chat_threads (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL UNIQUE REFERENCES groups(id) ON DELETE CASCADE,
  pinned_message_id uuid,                          -- FK added after group_messages exists
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE group_messages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id     uuid NOT NULL REFERENCES group_chat_threads(id) ON DELETE CASCADE,
  sender_id     uuid REFERENCES accounts(id) ON DELETE SET NULL,  -- null for system messages / deleted users
  kind          message_kind NOT NULL DEFAULT 'user',
  body          text NOT NULL,
  quoted_message_id uuid REFERENCES group_messages(id) ON DELETE SET NULL,  -- reply context
  reactions     jsonb NOT NULL DEFAULT '{}'::jsonb,  -- { "🔥": [account_id,...] }
  sent_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_group_messages_thread_time ON group_messages(thread_id, sent_at);
-- Late FK: pinned message points at a real message.
ALTER TABLE group_chat_threads
  ADD CONSTRAINT fk_pinned_message
  FOREIGN KEY (pinned_message_id) REFERENCES group_messages(id) ON DELETE SET NULL;
COMMENT ON TABLE group_messages IS 'System messages (kind=system, sender null) announce joins/leaves/check-ins/status. Rendered first-name + emoji only. Chat is members-only; deleted on leave per privacy policy.';

-- Per-user unread / read-state for chats (cheap unread-badge counting).
CREATE TABLE chat_read_state (
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  thread_id     uuid NOT NULL REFERENCES group_chat_threads(id) ON DELETE CASCADE,
  last_read_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, thread_id)
);
COMMENT ON TABLE chat_read_state IS 'Unread = messages in thread with sent_at > last_read_at. Powers the unread-chats badge.';

-- ============================================================================
-- SAFETY: blocks, reports, take-a-break (break_until lives on accounts)
-- ============================================================================

-- Blocks (directional, PRIVATE — blocked user is never notified; not removed from
-- shared groups, just can't DM/view). Blocking also drops any friendship in app.
CREATE TABLE blocks (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  blocked_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  reason        text,                             -- optional private note
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (blocker_id <> blocked_id),
  UNIQUE (blocker_id, blocked_id)
);
CREATE INDEX idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_id);
COMMENT ON TABLE blocks IS 'Private block: blocked user never notified, stays in shared groups (hidden, not kicked), cannot DM/view blocker. Reason never exposed to the blocked user.';

-- Reports -> human moderation queue, 24h review SLA.
CREATE TABLE reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id   uuid REFERENCES accounts(id) ON DELETE SET NULL,  -- reporter privacy: never disclosed
  reported_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  reason        report_reason NOT NULL,
  description   text,
  group_id      uuid REFERENCES groups(id) ON DELETE SET NULL,    -- context
  message_id    uuid,                                             -- optional evidence pointer
  status        report_status NOT NULL DEFAULT 'submitted',
  action_taken  text,                             -- 'warning_sent','account_suspended','no_action'
  reviewed_by   uuid REFERENCES accounts(id) ON DELETE SET NULL,  -- moderator
  reviewed_at   timestamptz,
  reported_at   timestamptz NOT NULL DEFAULT now(),
  -- SLA deadline (24h). Sweep job escalates rows past due_at still un-reviewed.
  due_at        timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_reports_updated BEFORE UPDATE ON reports
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
-- Moderation queue: open cases past/near SLA, oldest first:
CREATE INDEX idx_reports_open_sla ON reports(due_at)
  WHERE status IN ('submitted','under_review');
CREATE INDEX idx_reports_reported ON reports(reported_id);
COMMENT ON TABLE reports IS 'Human review within 24h (due_at). No public voting/ranking. Reporter identity never disclosed to the reported user.';

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

CREATE TABLE notifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  type          notification_type NOT NULL,
  title         text NOT NULL,
  body          text,
  related_entity_id uuid,                          -- group_id / account_id / offer_id, by type
  muted_until   timestamptz,                       -- 1h / 8h / tomorrow / until event ends
  seen_at       timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
-- Unread badge / inbox hot path (newest unread first):
CREATE INDEX idx_notifications_unread ON notifications(account_id, created_at DESC)
  WHERE seen_at IS NULL;
COMMENT ON TABLE notifications IS 'Delivery is gated by user_settings.notif_* per type before a row is created. muted_until suppresses surfacing within the window. Localized to preferred_locale.';

-- ============================================================================
-- FEEDBACK (post-hang survey -> shapes future matching)
-- ============================================================================

CREATE TABLE group_feedback (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  activity_rating smallint CHECK (activity_rating BETWEEN 0 AND 5),
  venue_rating    smallint CHECK (venue_rating BETWEEN 0 AND 5),
  vibe_rating     smallint CHECK (vibe_rating BETWEEN 0 AND 5),
  note          text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, account_id)
);
COMMENT ON TABLE group_feedback IS 'Post-hang survey (openFeedback). new-friends added during feedback create friend_requests/friendships separately.';

-- ============================================================================
-- i18n: generic translations table (canonical-English rows + per-locale strings)
-- ============================================================================

-- One row per (entity_type, entity_key, field, locale). Canonical English lives
-- on the catalog tables; this holds the FR-CA (and any future) strings applied at
-- render. See header for the rationale (Bill 96 scalability, data-only additions,
-- parity auditability).
CREATE TABLE translations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL,        -- 'activity','interest','archetype','quiz_question',
                                    -- 'quiz_option','activity_badge','category','group','venue_excluded'
  entity_key  text NOT NULL,        -- the canonical key/id (e.g. activity id, archetype key)
  field       text NOT NULL,        -- 'name','vibe','plan_b','badge','label','tag','personality', etc.
  locale      locale NOT NULL,
  value       text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entity_type, entity_key, field, locale)
);
CREATE TRIGGER trg_translations_updated BEFORE UPDATE ON translations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_translations_lookup ON translations(entity_type, entity_key, locale);
COMMENT ON TABLE translations IS
  'Generic i18n store. Canonical English on catalog tables; FR-CA (and future locales) here, applied at render — matching the demo''s *_FR dicts (ACTFR/INT_FR/ARFR/...). Proper nouns (names, usernames, venue names) are NEVER translated and have no rows here. Parity = a row exists per (entity,field) for each non-en locale (the check-i18n equivalent).';

-- ============================================================================
-- LAW 25 / PIPEDA / BILL 96 COMPLIANCE
-- ============================================================================

-- Point-in-time consent records (Law 25 / PIPEDA). The terms screen captures
-- consent to all 5 docs at once; one row per (account, kind) with the version + IP
-- + user agent + locale shown (Bill 96 audit: which language variant was served).
CREATE TABLE consent_records (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind          consent_kind NOT NULL,
  granted       boolean NOT NULL DEFAULT true,    -- false = withdrawn
  doc_version_id uuid,                             -- FK to legal_documents (for doc-backed consents)
  locale_shown  locale,                           -- Bill 96: which language variant the user saw
  ip_address    inet,                             -- jurisdiction inference
  user_agent    text,
  recorded_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_consent_account ON consent_records(account_id, kind, recorded_at DESC);
COMMENT ON TABLE consent_records IS 'Law 25/PIPEDA: consent before processing. Age 18+, terms/privacy/guidelines at the terms screen. locale_shown audits Bill 96. Re-consent required when a doc version advances past the consented one.';

-- Versioned, bilingual legal documents (the 5 docs, en + fr-CA). Each (doc,locale,
-- version) is one immutable row. Stored separately from `translations` because
-- they are large independently-versioned blobs that must be consented to.
CREATE TABLE legal_documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_key       legal_doc_key NOT NULL,
  locale        locale NOT NULL,
  version       text NOT NULL,                    -- e.g. 'v2'
  content_html  text NOT NULL,
  content_hash  text NOT NULL,                    -- for re-consent detection
  effective_at  timestamptz NOT NULL DEFAULT now(),
  is_current    boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (doc_key, locale, version)
);
-- One current version per (doc, locale):
CREATE UNIQUE INDEX uq_current_legal_doc ON legal_documents(doc_key, locale)
  WHERE is_current;
COMMENT ON TABLE legal_documents IS 'Bill 96/Law 25: each doc must exist with equal-quality content in en AND fr-CA. Uses LEGAL placeholder entity names (pending attorney review) — keep placeholders. Versioned for re-consent.';

-- Add the deferred FK from consent to a specific legal doc version.
ALTER TABLE consent_records
  ADD CONSTRAINT fk_consent_doc_version
  FOREIGN KEY (doc_version_id) REFERENCES legal_documents(id) ON DELETE SET NULL;

-- Explicit acceptance ledger linking a user to the exact doc version accepted.
CREATE TABLE legal_acceptances (
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  doc_version_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
  accepted_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, doc_version_id)
);
COMMENT ON TABLE legal_acceptances IS 'Which exact doc version each user accepted. Login compares is_current version hash vs accepted; mismatch => re-consent prompt.';

-- Law 25 data export requests (right to portability, machine-readable, ~15 days).
CREATE TABLE data_export_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  status        dsr_status NOT NULL DEFAULT 'requested',
  requested_at  timestamptz NOT NULL DEFAULT now(),
  completed_at  timestamptz,
  export_url    text,                             -- signed, short-lived link to the archive
  format        text NOT NULL DEFAULT 'json',     -- json | csv | pdf
  requested_ip  inet,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_export_updated BEFORE UPDATE ON data_export_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
COMMENT ON TABLE data_export_requests IS 'Law 25 right of access: full JSON archive (profile, messages, activity, settings, consent, connections) within 15 days.';

-- Law 25 deletion requests (in-app, permanent). The actual scrub happens in jobs;
-- this row tracks the request + the minimal retained metadata rationale.
CREATE TABLE data_deletion_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  status        dsr_status NOT NULL DEFAULT 'requested',
  requested_at  timestamptz NOT NULL DEFAULT now(),
  hard_delete_after timestamptz,                  -- e.g. requested_at + 30d before hard delete
  completed_at  timestamptz,
  reason        text,
  requested_ip  inet,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_deletion_updated BEFORE UPDATE ON data_deletion_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
COMMENT ON TABLE data_deletion_requests IS 'In-app permanent deletion. PII scrubbed (profile, messages anonymized); accounts row retained (id, *_hash, deleted_at) for dispute + re-registration block (~90d). Account deletion is in-app and permanent.';

-- Append-only audit log (consent changes, exports, deletions, moderation actions,
-- verification, admin actions). Supports Law 25 accountability.
CREATE TABLE audit_log (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id      uuid REFERENCES accounts(id) ON DELETE SET NULL,  -- who acted (null = system)
  subject_id    uuid REFERENCES accounts(id) ON DELETE SET NULL,  -- whom it concerns
  action        text NOT NULL,                    -- 'consent.grant','data.export','account.delete',
                                                  -- 'report.action','verify.success','age.attest', ...
  entity_type   text,
  entity_id     uuid,
  metadata      jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address    inet,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_subject ON audit_log(subject_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_log(action, created_at DESC);
COMMENT ON TABLE audit_log IS 'Append-only accountability trail (Law 25). Records consent/export/deletion/moderation/verification/age-attestation events with actor, subject, IP.';

-- ============================================================================
-- SEED: reserved usernames (RESERVED_NAMES) — enforced by username availability.
-- ============================================================================
INSERT INTO reserved_usernames(username) VALUES
  ('perch'),('admin'),('you'),('root'),('support'),('help'),('staff')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- END schema.sql
-- ============================================================================
