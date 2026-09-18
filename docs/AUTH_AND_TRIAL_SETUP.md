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
