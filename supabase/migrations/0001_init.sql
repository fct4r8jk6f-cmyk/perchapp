-- ============================================================================
-- Perch — thin-slice backend for Supabase (0001_init.sql)
-- ============================================================================
--
-- WHAT THIS IS
-- ------------
-- The minimum REAL backend to take Perch from "simulated demo" to "a person can
-- sign in, see this Thursday's group, book a spot, chat, and check in" — running
-- on Supabase's free tier. It is a focused subset of docs/schema.sql (the full
-- production design); the rest (waitlist/backfill, friends/DMs, Perch+, Law 25
-- surface, i18n table, …) lands in later migrations once this path is proven.
--
-- HOW TO RUN IT (no CLI needed)
-- -----------------------------
--   1. Create a free project at supabase.com.
--   2. Open the project's SQL Editor → New query → paste this ENTIRE file → Run.
--   3. That's it — schema, security, functions, and a seeded Thursday group are
--      all created in one shot. Re-running is safe (idempotent).
-- See docs/DEPLOY.md for the full walkthrough.
--
-- SECURITY MODEL
-- --------------
-- Row-Level Security is ON for every table. Reads are gated by RLS policies; the
-- invariant-bearing WRITES (the weekly cap, the join funnel, check-in) are
-- SECURITY DEFINER functions — the only way to create a membership/check-in — so a
-- client with the public anon key CANNOT bypass the cap, oversubscribe a group,
-- or forge a reservation code. This mirrors the demo's requestJoin()/checkIn()
-- funnel, but server-authoritative.
-- ============================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()

-- Shared updated_at trigger ---------------------------------------------------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- TABLES
-- ============================================================================

-- Reserved usernames (RESERVED_NAMES) — checked by username_available().
create table if not exists public.reserved_usernames (
  username text primary key
);

-- On-demand profile. 1:1 with auth.users — NOT created at sign-in, but at the
-- first join/host (openProfileSetup). Browsing is free without a profile row;
-- a row existing + profile_complete=true is the gate the join funnel checks.
create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  name             text not null check (char_length(name) between 1 and 30),  -- first name
  username         text not null check (char_length(username) between 3 and 20
                                        and username ~ '^[a-z0-9._]+$'),
  emoji            text not null default '🙂',
  -- NOTE: bio + photo_url are deliberately NOT in this slice. They are friends-only
  -- (pre-friendship visibility = first name + emoji + archetype only), and RLS is
  -- row-level (can't hide a single column), so they land later in a separate
  -- private table with its own self/friends policy. Nothing private is exposed here.
  profile_key      text,                          -- archetype key from the quiz
  profile_complete boolean not null default false,
  subscription_tier text not null default 'free' check (subscription_tier in ('free','plus')),
  -- Reliability inputs (NOT a public score). attended bumped ONLY on check-in.
  attended         integer not null default 0 check (attended >= 0),
  checked_in       boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists uq_profiles_username on public.profiles (lower(username));
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

-- Activity templates (minimal). price IS NOT NULL => ticketed (pay-at-venue).
create table if not exists public.activities (
  id          text primary key,                   -- 'thursdays', 'trivia', …
  icon        text not null default '🗓️',
  name        text not null,                       -- canonical English
  venue_text  text,
  price       numeric(8,2) check (price is null or price >= 0),
  created_at  timestamptz not null default now()
);

-- A small group (4–6) around an activity. filled <= max_size is invariant; on
-- reaching max the group is full and the waitlist opens.
create table if not exists public.groups (
  id            uuid primary key default gen_random_uuid(),
  activity_id   text references public.activities(id) on delete set null,
  emoji         text not null default '🪶',
  name          text not null,
  when_text     text,                              -- 'Thu · 7:00 PM' (display)
  venue_text    text,
  starts_at     timestamptz,
  min_size      smallint not null default 4 check (min_size >= 2),
  max_size      smallint not null default 6 check (max_size between min_size and 10),
  filled        smallint not null default 0 check (filled >= 0),
  status        text not null default 'forming' check (status in ('forming','full','today','week','cancelled')),
  open_waitlist boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint filled_within_capacity check (filled <= max_size)
);
create trigger trg_groups_updated before update on public.groups
  for each row execute function public.set_updated_at();

-- The join ledger — what the weekly cap counts. One non-terminal membership per
-- (user, group). join_iso_week is set from a STABLE default (America/Toronto,
-- Perch's market) so the cap count is a cheap index lookup. Memberships are only
-- ever created by join_group() (SECURITY DEFINER) — no client INSERT policy.
create table if not exists public.group_memberships (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  account_id    uuid not null references public.profiles(id) on delete cascade,
  activity_id   text references public.activities(id) on delete set null,
  role          text not null default 'member' check (role in ('member','host')),
  status        text not null default 'active' check (status in ('active','waitlisted','left','attended','cancelled')),
  attended      boolean not null default false,
  joined_at     timestamptz not null default now(),
  left_at       timestamptz,
  -- ISO year-week of the join, Montreal-local. A column DEFAULT may be non-immutable
  -- (unlike a STORED generated column), so this is the clean way to get a cheap,
  -- index-friendly weekly bucket without the generated-column IMMUTABLE constraint.
  join_iso_week text not null default to_char(timezone('America/Toronto', now()), 'IYYY-IW'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists uq_one_active_membership
  on public.group_memberships(group_id, account_id) where status in ('active','attended');
create index if not exists idx_memberships_account on public.group_memberships(account_id, status);
create index if not exists idx_memberships_cap
  on public.group_memberships(account_id, join_iso_week) where status in ('active','attended');
create trigger trg_memberships_updated before update on public.group_memberships
  for each row execute function public.set_updated_at();

-- Reservation — the PCH-XXXX code shown at the venue. PAY-AT-VENUE: no card, no
-- payment instrument, no charge stored. One per membership.
create table if not exists public.reservations (
  id            uuid primary key default gen_random_uuid(),
  membership_id uuid not null unique references public.group_memberships(id) on delete cascade,
  code          text not null,
  ticket        boolean not null default false,
  price         numeric(8,2) check (price is null or price >= 0),
  created_at    timestamptz not null default now(),
  constraint resv_code_format check (code ~ '^PCH-[A-Z0-9]{4}$')
);
create unique index if not exists uq_reservation_code on public.reservations(code);

-- Group chat. System messages (kind='system', sender null) announce joins/check-ins.
create table if not exists public.group_messages (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups(id) on delete cascade,
  sender_id  uuid references public.profiles(id) on delete set null,
  kind       text not null default 'user' check (kind in ('user','system')),
  body       text not null check (char_length(body) between 1 and 2000),
  sent_at    timestamptz not null default now()
);
create index if not exists idx_group_messages_group_time on public.group_messages(group_id, sent_at);

-- Check-in ledger — idempotent per (user, group). Written only by check_in().
create table if not exists public.check_ins (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  account_id    uuid not null references public.profiles(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  unique (group_id, account_id)
);
create index if not exists idx_checkins_account on public.check_ins(account_id);

-- Fuller UPDATE payloads over Realtime (so 'filled' changes carry the whole row):
alter table public.groups replica identity full;
alter table public.group_memberships replica identity full;

-- ============================================================================
-- FUNCTIONS  (all SECURITY DEFINER ones pin search_path = public)
-- ============================================================================

-- resvCode(): PCH- + 4 unambiguous chars, unique.
create or replace function public.gen_resv_code() returns text
language plpgsql as $$
declare
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';  -- no I,O,0,1
  code text;
  i int;
begin
  loop
    code := 'PCH-';
    for i in 1..4 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.reservations r where r.code = code);
  end loop;
  return code;
end;
$$;

-- Membership test without recursive RLS (used inside group_messages/membership policies).
create or replace function public.is_group_member(gid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.group_memberships m
    where m.group_id = gid and m.account_id = auth.uid()
      and m.status in ('active','attended')
  );
$$;

-- usernameStatus(): 3–20 chars, [a-z0-9._], not taken, not reserved.
-- Production TODO: rate-limit this at the app/edge (e.g. 10/min/IP) — an unbounded
-- caller could enumerate taken usernames. Not gating for the slice.
create or replace function public.username_available(uname text) returns boolean
language sql security definer stable set search_path = public as $$
  select char_length(uname) between 3 and 20
     and uname ~ '^[a-z0-9._]+$'
     and not exists (select 1 from public.profiles p where lower(p.username) = lower(uname))
     and not exists (select 1 from public.reserved_usernames r where lower(r.username) = lower(uname));
$$;

-- Confirmed joins in the current Montreal-local ISO week (cap counter).
create or replace function public.weekly_join_count() returns integer
language sql security definer stable set search_path = public as $$
  select count(*)::int from public.group_memberships m
  where m.account_id = auth.uid()
    and m.status in ('active','attended')
    and m.join_iso_week = to_char(timezone('America/Toronto', now()), 'IYYY-IW');
$$;

-- The join funnel: cap -> profile gate -> capacity -> membership + reservation +
-- filled bump + system message. Returns {ok, error?, code?, ticket?, price?}.
create or replace function public.join_group(p_group_id uuid, p_activity_id text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_complete boolean;
  v_tier text;
  v_name text;
  v_cap int;
  v_count int;
  v_grp public.groups%rowtype;
  v_price numeric(8,2);
  v_ticket boolean := false;
  v_membership_id uuid;
  v_code text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- Serialize concurrent joins by the SAME user so the weekly-cap check below
  -- cannot be raced (two parallel calls both reading count < cap and both
  -- inserting). The lock is per-user and released at transaction (function) end.
  perform pg_advisory_xact_lock(hashtext('perch_join:' || v_uid::text)::bigint);

  select p.profile_complete, p.subscription_tier, p.name
    into v_complete, v_tier, v_name
    from public.profiles p where p.id = v_uid;
  if v_complete is distinct from true then
    return jsonb_build_object('ok', false, 'error', 'profile_incomplete');
  end if;

  -- Free = 2 confirmed joins/ISO-week; Plus = 5. The 3rd hits the paywall.
  v_cap := case when v_tier = 'plus' then 5 else 2 end;
  select count(*) into v_count from public.group_memberships m
    where m.account_id = v_uid and m.status in ('active','attended')
      and m.join_iso_week = to_char(timezone('America/Toronto', now()), 'IYYY-IW');
  if v_count >= v_cap then
    return jsonb_build_object('ok', false, 'error', 'cap', 'cap', v_cap);
  end if;

  select * into v_grp from public.groups where id = p_group_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if exists (select 1 from public.group_memberships m
             where m.group_id = p_group_id and m.account_id = v_uid
               and m.status in ('active','attended')) then
    return jsonb_build_object('ok', false, 'error', 'already_joined');
  end if;

  if v_grp.filled >= v_grp.max_size then
    return jsonb_build_object('ok', false, 'error', 'full');
  end if;

  select a.price into v_price from public.activities a
    where a.id = coalesce(p_activity_id, v_grp.activity_id);
  v_ticket := v_price is not null;

  insert into public.group_memberships (group_id, account_id, activity_id, status)
    values (p_group_id, v_uid, coalesce(p_activity_id, v_grp.activity_id), 'active')
    returning id into v_membership_id;

  v_code := public.gen_resv_code();
  insert into public.reservations (membership_id, code, ticket, price)
    values (v_membership_id, v_code, v_ticket, v_price);

  update public.groups
    set filled = filled + 1,
        status = case when filled + 1 >= max_size then 'full' else status end,
        open_waitlist = (filled + 1 >= max_size)
    where id = p_group_id;

  insert into public.group_messages (group_id, sender_id, kind, body)
    values (p_group_id, null, 'system', coalesce(v_name, 'Someone') || ' joined the group');

  return jsonb_build_object('ok', true, 'code', v_code, 'ticket', v_ticket,
                            'price', v_price, 'membership_id', v_membership_id);
end;
$$;

-- checkIn(): idempotent. First-ever check-in bumps attended -> derived reliability.
create or replace function public.check_in(p_group_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_is_member boolean;
  v_rc int;
  v_first boolean := false;
  v_attended int;
  v_name text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select exists (select 1 from public.group_memberships m
    where m.group_id = p_group_id and m.account_id = v_uid
      and m.status in ('active','attended')) into v_is_member;
  if not v_is_member then
    return jsonb_build_object('ok', false, 'error', 'not_member');
  end if;

  insert into public.check_ins (group_id, account_id)
    values (p_group_id, v_uid)
    on conflict (group_id, account_id) do nothing;
  get diagnostics v_rc = row_count;
  v_first := v_rc > 0;

  if v_first then
    update public.profiles set attended = attended + 1, checked_in = true
      where id = v_uid returning attended, name into v_attended, v_name;
    update public.group_memberships set status = 'attended', attended = true
      where group_id = p_group_id and account_id = v_uid;
    insert into public.group_messages (group_id, sender_id, kind, body)
      values (p_group_id, null, 'system', coalesce(v_name, 'Someone') || ' checked in');
  else
    select attended into v_attended from public.profiles where id = v_uid;
  end if;

  return jsonb_build_object('ok', true, 'attended', v_attended, 'first_time', v_first);
end;
$$;

-- ============================================================================
-- GRANTS  (RLS still gates row visibility; these just open the door to the role)
-- ============================================================================
grant select on public.activities, public.groups to anon, authenticated;
grant select on public.profiles, public.group_memberships, public.reservations,
                public.group_messages, public.check_ins to authenticated;
grant insert on public.group_messages to authenticated;
grant insert, update on public.profiles to authenticated;

grant execute on function public.username_available(text)        to authenticated;
grant execute on function public.weekly_join_count()             to authenticated;
grant execute on function public.join_group(uuid, text)          to authenticated;
grant execute on function public.check_in(uuid)                  to authenticated;

-- ============================================================================
-- ROW-LEVEL SECURITY
-- ============================================================================
alter table public.reserved_usernames enable row level security;  -- no policy => only SECURITY DEFINER fns read it
alter table public.profiles           enable row level security;
alter table public.activities         enable row level security;
alter table public.groups             enable row level security;
alter table public.group_memberships  enable row level security;
alter table public.reservations       enable row level security;
alter table public.group_messages     enable row level security;
alter table public.check_ins          enable row level security;

-- profiles: anyone signed in can read (roster + chat sender names); you write only
-- your own. Safe to expose: this slice stores only first name + emoji + @username +
-- archetype — all intentionally member-visible. Private fields (bio/photo) aren't
-- stored here yet; they arrive with a self/friends policy in a later migration.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- catalog: world-readable (browsing is free, even pre-auth).
drop policy if exists activities_select on public.activities;
create policy activities_select on public.activities for select to anon, authenticated using (true);
drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups for select to anon, authenticated using (true);
-- (no write policies on groups: filled/status change only via join_group)

-- memberships: see your own + your groups' rosters. No client writes (join_group only).
drop policy if exists memberships_select on public.group_memberships;
create policy memberships_select on public.group_memberships for select to authenticated
  using (account_id = auth.uid() or public.is_group_member(group_id));

-- reservations: only your own codes.
drop policy if exists reservations_select on public.reservations;
create policy reservations_select on public.reservations for select to authenticated
  using (exists (select 1 from public.group_memberships m
                 where m.id = membership_id and m.account_id = auth.uid()));

-- group chat: members read; members post (user messages only — system msgs via fns).
drop policy if exists messages_select on public.group_messages;
create policy messages_select on public.group_messages for select to authenticated
  using (public.is_group_member(group_id));
drop policy if exists messages_insert on public.group_messages;
create policy messages_insert on public.group_messages for insert to authenticated
  with check (sender_id = auth.uid() and kind = 'user' and public.is_group_member(group_id));

-- check-ins: members read; no client writes (check_in only).
drop policy if exists checkins_select on public.check_ins;
create policy checkins_select on public.check_ins for select to authenticated
  using (account_id = auth.uid() or public.is_group_member(group_id));

-- ============================================================================
-- REALTIME  (postgres_changes respects RLS — subscribers only get rows they can read)
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'group_messages') then
    alter publication supabase_realtime add table public.group_messages;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'groups') then
    alter publication supabase_realtime add table public.groups;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'group_memberships') then
    alter publication supabase_realtime add table public.group_memberships;
  end if;
end $$;

-- ============================================================================
-- SEED  (idempotent): reserved names + one forming Thursday group to book into.
-- ============================================================================
insert into public.reserved_usernames (username) values
  ('perch'),('admin'),('you'),('root'),('support'),('help'),('staff')
  on conflict do nothing;

insert into public.activities (id, icon, name, venue_text, price) values
  ('thursdays', '🪶', 'Perch Thursday', 'Café Olimpico · Mile End', null)
  on conflict (id) do nothing;

insert into public.groups (id, activity_id, emoji, name, when_text, venue_text, starts_at, min_size, max_size, filled, status)
  values ('11111111-1111-1111-1111-111111111111', 'thursdays', '🪶',
          'This Thursday''s Perch', 'Thu · 7:00 PM', 'Café Olimpico · Mile End',
          date_trunc('week', now()) + interval '3 days 19 hours', 4, 6, 0, 'forming')
  on conflict (id) do nothing;

insert into public.group_messages (group_id, sender_id, kind, body)
  select '11111111-1111-1111-1111-111111111111', null, 'system',
         'Welcome 👋 Your group forms here — say hi when you join.'
  where not exists (
    select 1 from public.group_messages
    where group_id = '11111111-1111-1111-1111-111111111111' and kind = 'system'
  );

-- ============================================================================
-- END 0001_init.sql
-- ============================================================================
