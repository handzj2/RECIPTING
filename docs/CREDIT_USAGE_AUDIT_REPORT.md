# Credit usage — system audit report

**Date:** 2026-09-22  
**Scope:** HandzJ receipt-pack ledger (migrations 014–017)

---

## 1. What is audited

Every credit movement is an immutable row in `receipt_credit_ledger`:

| entry_type | Meaning | credits_delta |
|------------|---------|---------------|
| `purchase` | Pack activated or free/admin grant | +N |
| `consumption` | Receipt successfully issued | −1 |
| `adjustment` | Admin correction | ±N |
| `expiry` | Credits expired (long-stop) | −N |
| `refund` | Credits reversed | −N |

Each row stores:
- `business_id`
- `purchase_id` and/or `receipt_id` (traceability)
- `credits_delta` and `balance_after` (running balance)
- `note`, `created_by`, `created_at`

**Viewing, downloading, sharing, QR verification, and voiding never write to this ledger.**

---

## 2. Enforcement points (who can spend a credit)

| Gate | When | Failure code |
|------|------|--------------|
| `issuance_status()` | Read-only check | — |
| `next_receipt_no()` | Before allocating a number | `NO_CREDITS` / `TRIAL_EXPIRED` / `ACCOUNT_BLOCKED` |
| BEFORE INSERT trigger | Direct insert attempt | Same |
| AFTER INSERT consume trigger | Successful VALID insert | `NO_CREDITS` if race |

Subscription and active trial **skip** consumption (unlimited path).

---

## 3. Audit surfaces (after migration 017)

### Merchant

```sql
select * from my_credit_summary();
select * from my_credit_ledger(50);
```

Shows: remaining, purchased, consumed, each movement with receipt number or pack code.

### Platform admin

| RPC | Purpose |
|-----|---------|
| `admin_credit_ledger(biz, limit)` | Full history for one business |
| `admin_credit_usage_feed(type, limit)` | Platform-wide feed (filter by type) |
| `admin_business_credit_audit(limit)` | Snapshot: purchased / consumed / remaining / balance_ok |
| `admin_credit_integrity(biz)` | Reconcile sum(deltas) vs running balance |
| `admin_credit_daily_usage(days)` | Daily consumptions, grants, revenue |
| `admin_pack_stats()` | High-level pack sales + credit totals |

Consumptions and purchases are also mirrored into `platform_events` (`credit_consumption`, `credit_purchase`, …) for a unified ops timeline.

---

## 4. Integrity rules

For any business:

```
remaining = purchased + adjustments − consumed − expired − refunded
```

`admin_credit_integrity(business_id)` checks:

1. `sum(credits_delta)` equals latest `balance_after`
2. That equals `receipt_credits_remaining(business_id)`

`admin_business_credit_audit` exposes `balance_ok` per business so mismatches surface in one list.

---

## 5. Gaps found and status

| Gap | Risk | Status |
|-----|------|--------|
| No merchant-facing ledger history | Customer dispute “I bought 100, why 17?” | **Fixed** — `my_credit_ledger` |
| No admin per-business ledger UI data | Hard to investigate | **Fixed** — `admin_credit_ledger` |
| No platform-wide consumption feed | Cannot spot abuse patterns | **Fixed** — `admin_credit_usage_feed` |
| No daily usage rollup | Weak unit-economics visibility | **Fixed** — `admin_credit_daily_usage` |
| Balance not reconcilable in one call | Silent drift possible | **Fixed** — `admin_credit_integrity` + `balance_ok` |
| Credits not in `platform_events` | Split audit trails | **Fixed** — trigger mirrors ledger inserts |
| Race: two concurrent issues at balance 1 | Double spend | Mitigated: AFTER INSERT fails second if bal < 1; prefer serializable if volume grows |
| Expiry not automated | Dormant liability | Commercial rule only (24-month long-stop on purchase); no cron yet — optional follow-up |
| Subscription path never logged as “free issue” | Harder to compare pack vs sub usage | By design; sub issuances appear in `receipts` only |

---

## 6. Recommended admin checks (weekly)

```sql
-- 1. Anyone with broken ledger math?
select business_name, credits_purchased, credits_consumed, credits_remaining, balance_ok
from admin_business_credit_audit(500)
where balance_ok = false;

-- 2. Last 7 days usage
select * from admin_credit_daily_usage(7);

-- 3. Recent consumptions
select * from admin_credit_usage_feed('consumption', 30);

-- 4. Recent pack activations
select * from admin_list_pack_purchases(30);

-- 5. Spot-check one business
select * from admin_credit_integrity('<uuid>');
select * from admin_credit_ledger('<uuid>', 50);
```

---

## 7. Customer dispute playbook

When a merchant says “I bought 100, why do I only have 17?”:

1. `admin_credit_ledger(business_id, 200)`  
2. Sum `purchase` rows → should be 100 (or more if multiple packs)  
3. Count `consumption` rows → should be 83  
4. Latest `balance_after` → 17  
5. Each consumption row links to `receipt_no` — prove each issue  

If `admin_credit_integrity` reports inconsistent, stop and inspect order of `created_at` / missing rows before adjusting.

Admin correction (if needed):

```sql
-- Prefer a documented adjustment, not a silent edit
select admin_grant_credits('<biz>', 1, 'Correction: ticket #…');
-- or insert adjustment entry via a dedicated admin_adjust_credits if you add one
```

---

## 8. Files

| File | Role |
|------|------|
| `014_receipt_packs_ledger.sql` | Ledger table + consume on issue |
| `015_admin_pack_control.sql` | Pricing control + pack activation |
| `016_usage_based_credit_limits.sql` | Hard blocks (`NO_CREDITS`) |
| **`017_credit_usage_audit.sql`** | Audit RPCs + integrity + platform_events mirror |

Run **017** after 014–016 in Supabase SQL Editor.
