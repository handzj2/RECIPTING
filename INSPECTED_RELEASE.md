# HandzJ Digital Receipts — Inspected commercial release

**Build date:** 2026-09-22  
**Includes:** Receipt packs, usage-based credits, subscription payment ledger, admin pricing control, hardening

---

## What was hardened

| Area | Change |
|------|--------|
| Pack purchases | Full purchase + credit ledger (014) |
| Pack pricing | Admin UI + live catalog edits (015, admin.html) |
| Credit limits | NO_CREDITS / trial / subscription gates (016) |
| Credit audit | Integrity, daily usage, merchant ledger (017) |
| Subscriptions | Payment ledger + MoMo ref required path (018) |
| Hardening | Unique payment_ref, paid-pack admin-only, revoke direct writes (019) |
| Merchant app | Credits pill, lock issue button, loadCredits (app.html) |
| Admin app | Pack pricing, activate pack/sub with payment ref (admin.html) |

---

## SQL run order (Supabase)

**Already on production (base):** `supabase_schema` → 002 … 013

**New commercial layer — run in order:**

1. `sql/014_receipt_packs_ledger.sql`
2. `sql/015_admin_pack_control.sql`
3. `sql/016_usage_based_credit_limits.sql`
4. `sql/017_credit_usage_audit.sql`
5. `sql/018_subscription_billing_audit.sql`
6. `sql/019_hardening.sql`

---

## Pricing (default catalog)

| Product | Price (UGX) |
|---------|-------------|
| 5 free credits | 0 |
| 10 receipts | 5,000 |
| 20 receipts | 10,000 |
| 50 receipts | 20,000 |
| 100 receipts | 35,000 |
| 250 / 500 / 1,000 | 75k / 125k / 200k |
| Monthly subscription | 50,000 |
| Annual subscription | 500,000 |

Admin can change any pack/subscription price in the dashboard without redeploying code.

---

## Deploy

1. Run SQL 014→019 in Supabase  
2. Deploy `public/` (especially `app.html`, `admin.html`) to Vercel  
3. Confirm platform admin email is in `platform_admins`  
4. Test: grant free credits → issue → balance drops; activate pack with MoMo ref  

---

## Docs added

- `docs/USAGE_BASED_LIMITS.md`
- `docs/CREDIT_USAGE_AUDIT_REPORT.md`
- `docs/SUBSCRIPTION_BILLING_AUDIT_REPORT.md`
- `docs/PACK_PURCHASE_LEDGER_ANALYSIS.md`
- `docs/REVISED_PRICING_SUMMARY.md`
- `docs/PRICING_PAGE_COPY.md`
- `docs/UNIT_ECONOMICS_PAID_SUPABASE.md`
- `docs/IMPLEMENTATION_CHECKLIST.md`

---

## Security notes (019)

- Paid pack activation: platform admin only + payment_ref required  
- Unique index on pack and subscription `payment_ref` (active/completed)  
- Direct INSERT/UPDATE/DELETE revoked on commercial tables for `authenticated`/`anon` (RPC-only)  
- Credit consumption only on successful VALID receipt insert  
- View/share/verify/void never consume credits  
