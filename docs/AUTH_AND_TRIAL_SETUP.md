# Going multi-client: accounts, isolation, 5-day trial

Everything below is already in the code. This is the 15-minute setup to switch it on.

---

## 1. Run the migration

Supabase → **SQL Editor** → paste `sql/002_auth_multitenant.sql` → **Run**.

It is safe to re-run. It does four things:

| | |
|---|---|
| Tenant ownership | adds `owner_id`, `prefix`, `trial_ends_at`, `subscription_status` to `businesses` |
| Isolation | replaces the old `using (true)` policies with owner-scoped RLS on all three tables |
| Trial | `signup_business()` starts a **5-day** trial; `business_active()` is checked by the insert policy |
| Public verification | `verify_receipt(no, verify_id)` — the only thing an anonymous visitor can call |

## 2. Turn on email + password auth

Supabase → **Authentication → Providers → Email**: enabled (it is by default).

- **Confirm email ON** (recommended): signup sends a confirmation link, the tenant is created on first sign-in.
- **Confirm email OFF**: signup logs the user straight in and creates the tenant immediately.

Both paths are handled in the code — nothing to change either way.

Then **Authentication → URL Configuration**: set Site URL to your Vercel domain and add
`https://your-domain/login.html` to the redirect allow-list, so password resets land back in the app.

## 3. Claim the existing HandzJ data

Your current receipts belong to a business row with no owner — which now means *nobody* can see it.

1. Go to `/login.html?mode=signup` and create the account for `handzj2@gmail.com`.
2. **Delete** the duplicate business that signup just created for you (Table editor → `businesses`).
3. Uncomment the last block of `002_auth_multitenant.sql`, put in that same email, and run it. It attaches
   the original HANDZJ row — and every receipt hanging off it — to your login, marked `active` (no trial).

Verify with: `select name, owner_id, prefix, subscription_status from businesses;` — no row should have a null `owner_id`.

## 4. Deploy

`git push` (Vercel picks up `/public` as before). New routes: `/login.html`.

---

## How the isolation actually works

The anon key in `config.js` is still public — that is fine and intended. It now grants nothing on its own:

- `receipts` SELECT requires `business_id = my_business_id()`, which reads `auth.uid()` from the signed JWT. No session → zero rows. Another tenant's session → zero rows.
- `businesses` has **no policy for `anon` at all**.
- `receipt_sequences` has no client-side write policy; numbering happens inside `next_receipt_no()` (SECURITY DEFINER), which also allocates atomically — no more duplicate-number races between two open tabs.
- Customer verification links don't need a login and don't touch the tables: they call `verify_receipt()`, which requires **both** the receipt number and the verification ID (so numbers can't be walked), and returns the customer name and payment reference already masked by the database.

Worth knowing: the trial is enforced in the insert policy, not just the UI. Someone who opens the console and calls the API directly after their trial ends still gets rejected.

## What happens when a trial ends

Day 0–5: banner counts down, everything works.
After: the **Issue receipt** button is disabled, the database refuses inserts, and a subscribe panel appears in Settings.

Deliberately still allowed after expiry: viewing the log, printing, PDF download, sending, **voiding**, and all previously issued verification links. Expiry stops new issuance; it never strips a business of records it already has.

## Switching a client on after they pay

```sql
update businesses
   set subscription_status = 'active',
       subscribed_until = now() + interval '1 year'   -- or null for open-ended
 where email = 'client@example.com';
```

They see it on next refresh. To give someone more trial instead:
`update businesses set trial_ends_at = now() + interval '5 days' where ...`

Billing is manual on purpose — mobile money and bank transfer are how your market actually pays. When you want it automated, the hook is one column (`subscribed_until`) and a webhook that writes to it.

---

# Where a new account actually goes

A signup writes to **two** places, both in your Supabase project:

1. `auth.users` — the login itself (email + a hashed password). Supabase manages this table; you can see it under **Authentication → Users**. You never see their password, and neither does the app.
2. `businesses` — their tenant row: name, tagline, contacts, receipt prefix, `owner_id` pointing back at that user, and `trial_ends_at = now() + 5 days`.

Everything they then create (`receipts`, `receipt_sequences`) carries their `business_id`, which is how row level security keeps them apart.

Nothing is sent to you automatically. That's what the owner dashboard is for.

# Owner dashboard — `/admin.html`

Run `sql/003_admin_dashboard.sql` (edit the email at the bottom to yours first). Then open `/admin.html` while signed in.

It shows every business that has ever signed up: when they joined, whether they're on trial, how many days are left, how many receipts they've actually issued, the total value of those receipts, and when they were last active. New signups since your previous visit are tagged **NEW**.

The counters across the top are the ones worth watching daily: *trials ending ≤3d* is your call list, *trial ended* is who to chase, and *receipts issued* tells you who is genuinely using it versus who signed up and went quiet.

Four buttons per row do the billing work — **+1 month**, **+1 year**, **+5d trial**, **Cancel**. No SQL needed; the change reaches the client on their next refresh.

Access is enforced in the database, not the page. Every admin function starts with `is_platform_admin()`, so a tenant who opens `/admin.html` (or calls the API directly) gets zero rows and a refusal. Add another admin with:

```sql
insert into platform_admins (user_id, email)
select id, email from auth.users where email = 'colleague@example.com';
```

## Getting told about signups without opening the dashboard

The dashboard is pull, not push. If you want a ping, Supabase → **Database → Webhooks** → new webhook on `businesses` / INSERT, pointed at an email or WhatsApp service (Resend, Make, Zapier). The row it sends already contains the business name and email. That's a small add-on whenever you want it — the dashboard works without it.
