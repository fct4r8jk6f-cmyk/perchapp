-- ============================================================================
-- 0003 — Per-account rate limiting (abuse / spam mitigation, DB layer)
-- ============================================================================
-- The live thin slice had NO rate limiting (only a TODO on username_available).
-- Because config.js ships the public anon key, the RPCs are internet-reachable,
-- so this adds an app-layer throttle keyed by account_id for the AUTHENTICATED
-- write paths (chat sends, join, check-in) and authenticated username lookups.
--
-- LIMITS OF THIS LAYER (read before relying on it):
--   * Per-ACCOUNT, not per-IP. Postgres RPCs can't see the caller's IP, so an
--     unauthenticated/anon enumerator (e.g. hammering username_available without
--     a session) is NOT stopped here — that needs an edge/WAF in front
--     (Cloudflare). See docs/HARDENING.md. This is defence-in-depth, not the WAF.
--   * Fixed window (not sliding) — tolerates a small burst at window boundaries.
--
-- Idempotent: create-if-not-exists + create-or-replace + drop-trigger-if-exists.
-- The join_group / check_in / username_available bodies below are VERBATIM from
-- 0001 with a single rate-limit guard added — keep them in sync if 0001 changes.
-- ============================================================================

-- One row per (account, action). Tiny + bounded. No client access (RLS on, no
-- policy = default-deny); only the SECURITY DEFINER helpers below touch it.
create table if not exists public.rate_limits (
  account_id   uuid not null references auth.users(id) on delete cascade,
  action       text not null,
  window_start timestamptz not null default now(),
  count        integer not null default 0,
  primary key (account_id, action)
);
alter table public.rate_limits enable row level security;

-- Returns true if the caller is allowed to perform p_action again within the
-- fixed window, false if they're over p_max. Records the attempt. Fail-OPEN for
-- anon (no account to key on) so it never breaks unauthenticated flows — anon
-- abuse is the edge layer's job.
create or replace function public.rl_check(p_action text, p_max int, p_window interval)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then
    return true;  -- untrackable; handled at the edge
  end if;
  insert into public.rate_limits (account_id, action, window_start, count)
    values (v_uid, p_action, now(), 1)
  on conflict (account_id, action) do update
    set count = case when public.rate_limits.window_start < now() - p_window then 1
                     else public.rate_limits.count + 1 end,
        window_start = case when public.rate_limits.window_start < now() - p_window then now()
                            else public.rate_limits.window_start end
  returning count into v_count;
  return v_count <= p_max;
end;
$$;

-- ---------------------------------------------------------------------------
-- Chat-spam guard: throttle USER message inserts (system messages are exempt —
-- they're posted by join_group/check_in and carry the real uid otherwise).
-- ---------------------------------------------------------------------------
create or replace function public.rl_message_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if NEW.kind = 'user' and not public.rl_check('msg', 20, interval '1 minute') then
    raise exception 'rate_limited' using errcode = 'check_violation';
  end if;
  return NEW;
end;
$$;
drop trigger if exists trg_rl_message on public.group_messages;
create trigger trg_rl_message before insert on public.group_messages
  for each row execute function public.rl_message_guard();

-- ---------------------------------------------------------------------------
-- username_available — 0001 body + a per-account guard (authenticated callers).
-- Now VOLATILE (was STABLE) because rl_check writes. Anon enumeration still
-- needs the edge (see header).
-- ---------------------------------------------------------------------------
create or replace function public.username_available(uname text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.rl_check('uname', 20, interval '1 minute') then
    return false;
  end if;
  return char_length(uname) between 3 and 20
     and uname ~ '^[a-z0-9._]+$'
     and not exists (select 1 from public.profiles p where lower(p.username) = lower(uname))
     and not exists (select 1 from public.reserved_usernames r where lower(r.username) = lower(uname));
end;
$$;

-- ---------------------------------------------------------------------------
-- join_group — 0001 body + a rate-limit guard after the auth check.
-- ---------------------------------------------------------------------------
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

  if not public.rl_check('join', 8, interval '1 minute') then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
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

-- ---------------------------------------------------------------------------
-- check_in — 0001 body + a rate-limit guard after the auth check.
-- ---------------------------------------------------------------------------
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

  if not public.rl_check('checkin', 12, interval '1 minute') then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
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
