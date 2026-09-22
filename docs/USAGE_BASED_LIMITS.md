# Usage-based credit limits — implemented

## Behaviour

| Situation | Can issue? | Credit consumed? |
|-----------|------------|------------------|
| Active monthly/annual subscription | Yes (unlimited*) | No |
| Free trial still running | Yes | No |
| Pack credits remaining > 0 | Yes | **1 credit** on successful issue |
| Trial ended + 0 credits + no subscription | **No** | — |
| Account suspended / terminated | **No** | — |
| View / download / share / QR verify / void | Always | **Never** |

\*Fair-use; not a literal promise of infinite infrastructure.

## Database (run in order)

1. `014_receipt_packs_ledger.sql` — catalog, purchases, ledger, consume trigger  
2. `015_admin_pack_control.sql` — admin pricing UI RPCs + ENTRY_10 pack  
3. **`016_usage_based_credit_limits.sql`** — hard enforcement

### What 016 does

- **`business_active()`** — true if subscription **or** trial **or** credits > 0 (and not suspended)
- **`issuance_status()` / `my_issuance_status()`** — returns mode, credits, clear message
- **`next_receipt_no()`** — raises `NO_CREDITS` / `TRIAL_EXPIRED` / `ACCOUNT_BLOCKED` before allocating a number
- **BEFORE INSERT trigger** — same checks (defense in depth)
- **AFTER INSERT consume trigger** — deducts 1 credit only on VALID insert when not on sub/trial
- **`my_credit_summary()`** — extended with `issuance_mode`, `issuance_allowed`, `issuance_message`

## App (`public/app.html`)

Already patched in the extract:

- Loads `my_credit_summary` after login (`loadCredits`)
- Shows **credits pill** in the top bar (`N CREDITS` / `UNLIMITED`)
- Issue button locked when no credits and no trial/sub
- Clear user messages for `NO_CREDITS`
- Refreshes balance after each successful issue
- Viewing / sharing never touches credits

## Merchant experience

1. Signup → optional 5 free credits (via `grant_free_starter_credits`)  
2. Issues during trial without consuming pack credits  
3. After trial, remaining pack credits keep them issuing  
4. At 0 credits → “No credits — buy a pack” + link to pricing  
5. Buy ENTRY_10 (UGX 5,000) or larger → admin activates → balance updates  

## Admin experience

- Activate pack after MoMo → credits appear immediately  
- Grant promo credits  
- Monitor packs sold, revenue, credits granted/consumed/held  
- Change pack prices live without redeploy  

## Deploy checklist

```text
Supabase SQL Editor:
  1. Run 014_receipt_packs_ledger.sql
  2. Run 015_admin_pack_control.sql
  3. Run 016_usage_based_credit_limits.sql

Deploy updated public/app.html (and admin.html pack UI if not yet)

Optional after signup:
  select grant_free_starter_credits('<business_uuid>');
```

## Error codes the app understands

| Code | Meaning |
|------|---------|
| `NO_CREDITS` | Zero pack credits; buy pack or subscribe |
| `TRIAL_EXPIRED` | Trial over and no credits/sub |
| `ACCOUNT_BLOCKED` | Suspended or terminated |
