# Perch — Deploy & Backend Runbook

*From the simulated demo to a real, hosted product on free-tier infrastructure. This is the **Phase B** companion to [BOOTSTRAP.md](BOOTSTRAP.md) ("Lean web-app launch"). It covers exactly the steps that need **your** accounts — Claude has built everything up to this line.*

> ⚠️ **Not legal/tax/financial advice.** Free-tier limits and pricing change — verify on each provider. Keep the in-app legal docs flagged "pending attorney review" until counsel signs off (see [COUNSEL_BRIEF.md](COUNSEL_BRIEF.md)).

**Quick glossary** (skip if you know these): *Magic link* — an email that signs you in when you click it, no password. *Migration* — a SQL file that builds your database. *RLS (Row-Level Security)* — server rules that stop one user reading/writing another's data. *anon key* — your project's public API key (safe to ship; RLS is what protects data). *service_role key* — the admin key that bypasses RLS — **never** put it in frontend code.

---

## Where this fits

The demo (`index.html`) fakes its backend. This runbook stands up the **thin-slice real backend** — the critical path *sign in → set up profile → book this Thursday's group → group chat → check in* — on Supabase, and gets the site online. The full production design lives in [schema.sql](schema.sql) / [API.md](API.md) / [BACKEND.md](BACKEND.md); the slice is the first migration of that design.

**What's already in the repo (no account needed):**

| Path | What it is |
|---|---|
| [`supabase/migrations/0001_init.sql`](../supabase/migrations/0001_init.sql) | The thin-slice schema + Row-Level Security + cap/join/check-in functions + a seeded Thursday group. One paste. |
| [`supabase/migrations/0002_harden_profile_name.sql`](../supabase/migrations/0002_harden_profile_name.sql) | Defence-in-depth: blocks angle brackets in profile names at the data layer. Idempotent — apply after 0001 (and on the already-live DB). |
| [`supabase/migrations/0003_rate_limits.sql`](../supabase/migrations/0003_rate_limits.sql) | Per-account rate limiting on chat sends / join / check-in / username lookups. Idempotent. See [HARDENING.md](HARDENING.md) for the full abuse/DoS picture (CAPTCHA, WAF, alerts). |
| [`backend/perch-api.js`](../backend/perch-api.js) | The live data layer (auth, profile, group, chat+realtime, join, check-in). No build step. |
| [`backend/test.html`](../backend/test.html) | A smoke-test page that exercises the whole path so you can **prove the backend works before wiring it into the app**. |
| [`config.example.js`](../config.example.js) | Template for your Supabase URL + anon key. Copy to `config.js` (gitignored). |

---

## Step 1 — Create the Supabase project (free) · ~5 min

1. Sign up at [supabase.com](https://supabase.com) → **New project**.
2. Pick a name, a strong DB password (save it), and the **Central Canada / closest** region.
3. Wait for it to provision (~2 min).

## Step 2 — Run the migration · ~1 min

1. In the project: **SQL Editor → New query**.
2. Open [`supabase/migrations/0001_init.sql`](../supabase/migrations/0001_init.sql), copy the **entire** file, paste, click **Run**.
3. You should see "Success." It creates all tables, security policies, functions, and seeds one forming Thursday group. Re-running is safe.
4. Open [`supabase/migrations/0002_harden_profile_name.sql`](../supabase/migrations/0002_harden_profile_name.sql) in a new query, paste, **Run**. (Already-live project? Just run this one to apply the hardening.) Re-running is safe.
5. Open [`supabase/migrations/0003_rate_limits.sql`](../supabase/migrations/0003_rate_limits.sql) in a new query, paste, **Run** — adds per-account rate limiting. Then see [HARDENING.md](HARDENING.md) for the console/edge steps (CAPTCHA, Cloudflare WAF, alerts) that `0003` alone can't cover. Re-running is safe.

*(Optional, if you use the Supabase CLI later: `supabase db push` applies the same file. The CLI isn't required.)*

## Step 3 — Get your keys · ~1 min

1. **Project Settings → API** (gear icon, bottom-left).
2. Under **Project URL** copy the URL — it looks like `https://abcdefgh.supabase.co`.
3. Under **Project API keys** copy the key labelled **`anon` `public`** — a long string starting with `eyJ…`. **Do NOT** copy `service_role` (that one bypasses all security).
4. In the repo, copy `config.example.js` → **`config.js`** and paste both values in.
   - The **anon key is public by design** and safe in a frontend — RLS protects the data.
   - `config.js` is gitignored so your keys don't get committed by accident.

## Step 4 — Turn on email auth · ~2 min

The slice signs in with a **magic link** (no paid SMS — exactly the BOOTSTRAP money-saver). Three settings must be right or sign-in fails *silently*, so don't skip any:

1. **Authentication → Sign In / Providers → Email**: confirm **Email** shows a green **Enabled** indicator (it's on by default; if it says Disabled, turn it on). Make sure **Enable email signups** is on, and leave **Confirm email** **ON** — with it off, the magic link won't create a session.
2. **Authentication → URL Configuration → Redirect URLs**: add your local test URL **now** — `http://localhost:3000` (or `http://localhost:8000` if you use Python). This is **required** for the email link to return you to the page signed in, not optional/"later". Add your production domain here too once you deploy (Step 6).
3. *Optional — the 6-digit code path (a backup if clicking the link is awkward):* go to **Authentication → Email Templates → Magic Link** and add `{{ .Token }}` somewhere in the body. Those double braces are template syntax — Supabase replaces them with the 6-digit code. Then you can use the "Verify code" box on the test page instead of clicking the link.
4. *Email rate limit:* Supabase's built-in email allows only **~2 messages/hour per recipient** on the free tier. If you re-test with the same address you'll hit it and emails stop arriving — use different addresses (Gmail `you+1@`, `you+2@` aliases work) or wait. For real volume add a free SMTP (e.g. Resend) under **Authentication → SMTP** later.

## Step 5 — Smoke-test the backend · ~5 min

Serve the repo and open the test page (it needs a server, not `file://`, for ES modules + auth redirects):

```sh
npx serve .            # then open http://localhost:3000/backend/test.html
# or: python3 -m http.server 8000  -> http://localhost:8000/backend/test.html
```

Work top to bottom and watch the **Log** panel turn green:

1. **Sign in** — enter your email, send the link, then open that email **in the same browser window** and click it → it returns to the test page signed in. (Different browser or incognito? The session won't carry — use the **6-digit code** box instead, if you enabled it in Step 4.3.)
2. **Profile** — check a username (try a reserved one like `admin` → should be unavailable), then save.
3. **Group** — Load group → Book my spot → you get a `PCH-XXXX` code.
4. **Chat** — send a message; open a **second browser/incognito**, sign in with a different email, set up a profile, join the same group, and send — messages should appear **live** in both.
5. **Check in** — `attended` increments the first time, stays put on a repeat (idempotent).

**Cap check (proves the free tier is enforced server-side):** the seed has one group, so to really test the 2/week cap you'll need a couple more forming groups. (This assumes Step 2 ran — the `thursdays` activity must exist, or the insert below fails with a foreign-key error.) Quick way — in SQL Editor:

```sql
insert into public.groups (activity_id, emoji, name, when_text, venue_text, starts_at, max_size, status)
select 'thursdays','🪶','Test group '||g,'Thu · 7:00 PM','Test venue', now() + interval '7 days', 6, 'forming'
from generate_series(1,3) g;
```

Join 2, then try a 3rd → `join_group` returns `{ ok:false, error:"cap", cap:2 }`. That refusal is the paywall trigger, enforced in Postgres.

> ✅ **When every step is green, the backend is real and proven.** That's the green light to wire it into `index.html` (the data-layer work — see "What's next").

## Step 6 — Put the site online (free) · ~10 min

The frontend is a static PWA, so any static host works.

- **Vercel / Netlify / Cloudflare Pages**: connect the GitHub repo (or drag-and-drop the folder). **No build command, output dir = repo root** — this site has no build step, so don't pick a framework preset that expects one. You get a free `*.vercel.app` / `*.netlify.app` URL immediately.
- Add that production URL to Supabase **Redirect URLs** (Step 4.2). This doubles as CORS: Supabase only accepts browser requests from origins on that list, so a missing entry shows up as a CORS error (not a key problem).
- **How `config.js` ships (no build step, so env-var injection isn't automatic):** simplest path — since the anon key is **public by design**, just create a production `config.js` with your URL + anon key and let it deploy (it's safe; RLS is the protection). Because it's gitignored, either remove that ignore line for your deploy, or drag-drop/upload `config.js` alongside the files in the host's dashboard. Don't reach for `import.meta.env`/Vite env vars — there's no bundler here to substitute them.

## Step 7 — Custom domain (optional, ~$15/yr) · ~15 min + DNS wait

1. Buy a domain (Namecheap, Cloudflare Registrar, etc.).
2. In your host (Vercel/Netlify): **Add domain** → follow its DNS instructions (a CNAME/A record at your registrar). HTTPS is automatic.
3. Add the custom domain to Supabase **Redirect URLs** too.

DNS can take minutes to a few hours to propagate. The domain is genuinely the *last* and smallest step — the backend above is the real work.

---

## What's next (after the smoke test is green)

1. ~~**Wire `index.html` to the live backend.**~~ **Done.** A guarded `<script type="module">` bridge exposes `window.Perch`/`window.PERCH_LIVE`; the critical-path flows call it when `config.js` is present and fall back to the simulation when it isn't — sign-in (existing session + new-user magic-link), profile hydration + save, `requestJoin` → `join_group`, group chat (real history + realtime + send), `checkIn` → `check_in`. The Explore catalogue stays simulated by design (Perch Thursdays is the one real group). **To finish new-user sign-in cleanly, add custom SMTP (below) so the in-app 6-digit code works — until then, fresh sign-in uses the email magic link.**
2. **Grow the schema** beyond the slice — waitlist/backfill, friends/DMs, Perch+ billing state, the Law 25 surface, the i18n `translations` table — each a new `supabase/migrations/000N_*.sql`, all already designed in [schema.sql](schema.sql).
3. **Custom SMTP** (Resend free tier) so auth emails aren't rate-limited.
4. Only once it's working: **app stores** via Capacitor (Phase C, ~$124).

---

## Cost so far

| Item | Cost |
|---|---|
| Supabase (Postgres + Auth + Realtime) | **$0** (free tier) |
| Static hosting | **$0** (free tier) |
| Domain | **~$15/yr** (optional) |
| **Total to be live** | **~$0–15** |

The price of being real is the price of a domain — exactly what [BOOTSTRAP.md](BOOTSTRAP.md) promised.
