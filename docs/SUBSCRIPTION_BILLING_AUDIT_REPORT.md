# Subscription billing — system audit report

**Date:** 2026-09-22  
**Scope:** HandzJ monthly/annual subscription path (pre- and post-migration 018)

---

## 1. Current commercial model (as designed)

| Plan | Price | Duration | Activation |
|------|-------|----------|------------|
| Business Monthly | UGX 50,000 | 1 month | Manual Mobile Money → admin activates |
| Business Annual | UGX 500,000 | 12 months | Same |
| Free trial | UGX 0 | 5 days from signup | Automatic |

**No automatic MoMo API** in this phase. Admin activation is authoritative  
(`DOMAIN_AND_BILLING.md`, `pricing.html`, in-app subscribe panel).

---

## 2. What existed before this audit

### Strengths

| Area | Status |
|------|--------|
| Trial enforced in DB (`trial_ends_at`) | Working |
| Issuance gated by `business_active()` | Working |
| Admin can +1 month / +1 year from dashboard | Working |
| Admin can cancel / extend trial | Working |
| Stacking renewals (`greatest(subscribed_until, now()) + months`) | Working |
| Historical receipts remain readable after expiry | Working |
| Platform admin only (`is_platform_admin`) | Working |

### Critical gaps

| Gap | Risk | Severity |
|-----|------|----------|
| **No payment ledger for subscriptions** | Cannot prove who paid, how much, or with which MoMo ref | **Critical** |
| `admin_set_subscription` only flips flags | No amount, no payment_ref, no period record | **Critical** |
| No revenue reporting for subs | Pack revenue trackable; sub revenue invisible | High |
| `plan` column set inconsistently | `starter` vs `business` based only on months ≥ 12 | Medium |
| Cancel has no audit trail of *why* / *by whom* | Dispute / compliance weak | Medium |
| No “expiring in 7 days” operational list | Missed renewals | Medium |
| No merchant-visible payment history | Trust / support load | Medium |
| Packs and subs revenue not combined | Incomplete commercial dashboard | Medium |
| No catalog for sub prices | Price changes require code edits | Low–Medium |
| Open-ended sub (`p_months <= 0` → `subscribed_until = null`) | Unlimited liability if misused | Low |

Pack purchases already had `payment_ref` + ledger (014/015).  
**Subscriptions did not** — that asymmetry is the core finding.

---

## 3. Flow audit (as-is)

```
Merchant sees UGX 50,000 / 500,000 on pricing page
        ↓
Pays MTN or Airtel Money (off-platform)
        ↓
Emails/WhatsApps reference + login email to support
        ↓
Admin opens admin.html → clicks "+1 month" or "+1 year"
        ↓
admin_set_subscription(biz, 1|12)
        ↓
businesses.subscription_status = 'active'
businesses.subscribed_until   = now() + N months
        ↓
Merchant can issue again (unlimited while active)
```

**Missing in the middle:** no row that says  
“Business X paid UGX 50,000, ref MTN-123, for period Y→Z, activated by admin A.”

---

## 4. Fixes delivered in migration 018

| Addition | Purpose |
|----------|---------|
| `subscription_plan_catalog` | MONTHLY 50k / ANNUAL 500k — admin-editable prices |
| `subscription_payments` | Immutable payment + period ledger |
| `admin_record_subscription_payment(...)` | **Preferred** activate-with-payment path |
| Patched `admin_set_subscription` | Legacy buttons still work; now also write a payment row |
| `admin_list_subscription_payments` | Payment history for ops |
| `admin_subscription_billing_stats` | Revenue, active, expiring-7d, expired |
| `my_subscription_payments` | Merchant sees own payment history |
| `admin_commercial_revenue_summary` | Packs + subscriptions combined |
| `platform_events` mirror | `subscription_payment` / `subscription_cancelled` |

### Preferred admin activation (after MoMo)

```sql
select admin_record_subscription_payment(
  '<business_uuid>',
  'MONTHLY',        -- or 'ANNUAL'
  'MTN-XXXXXX',     -- payment reference (required in practice)
  null,             -- use catalog price
  null,             -- use catalog months
  'mobile_money',
  'Paid via MTN'
);
```

Legacy `+1 month` / `+1 year` buttons continue to work and now create a ledger row (method = `admin`, note marks legacy path).

---

## 5. Recommended admin checks (weekly)

```sql
-- Revenue overview
select * from admin_subscription_billing_stats();
select * from admin_commercial_revenue_summary();

-- Recent payments
select * from admin_list_subscription_payments(50);

-- Expiring within 7 days (from stats) + list them:
select id, name, email, subscribed_until
from businesses
where subscription_status = 'active'
  and subscribed_until is not null
  and subscribed_until > now()
  and subscribed_until <= now() + interval '7 days'
order by subscribed_until;

-- Expired but still flagged active (should renew or cancel)
select id, name, email, subscribed_until
from businesses
where subscription_status = 'active'
  and subscribed_until is not null
  and subscribed_until <= now();
```

---

## 6. Dispute playbook

Merchant: “I paid but still cannot issue.”

1. Find business in admin list → confirm `subscription_status` / `subscribed_until`.
2. `admin_list_subscription_payments` filtered by business (or SQL on `subscription_payments`).
3. Match `payment_ref` to MoMo SMS/statement.
4. If payment exists but status not active → re-run `admin_record_subscription_payment` or fix flags.
5. If no payment row → do not activate until ref is verified; then record with ref.

Merchant: “I was charged twice.”

1. List payments for that business by `payment_ref` and date.
2. Refund is commercial (MoMo); mark row `status = 'refunded'` if you add an admin helper, or note in `notes`.

---

## 7. Remaining recommendations (not in 018)

| Priority | Item |
|----------|------|
| High | Update admin UI: require payment ref when clicking +1 month / +1 year (call `admin_record_subscription_payment`) |
| High | Show “Expiring ≤7d” count on admin stats cards |
| Medium | Merchant settings page: show current period end + payment history |
| Medium | Optional: SMS/email reminder 3 days before `subscribed_until` |
| Low | Automatic MoMo collection API (future phase) |
| Low | Invoices/PDF receipts for the subscription payment itself |

---

## 8. Interaction with receipt packs

| Path | Billing record | Issuance |
|------|----------------|----------|
| Pack credits | `receipt_pack_purchases` + credit ledger | 1 credit per issue |
| Subscription | `subscription_payments` | Unlimited while `subscribed_until > now()` |
| Trial | none (time-boxed) | Unlimited for 5 days |

Both can coexist: active subscription skips credit consumption (016).  
After sub expires, remaining pack credits still allow issuance.

---

## 9. Files

| File | Role |
|------|------|
| `003_admin_dashboard.sql` | Original `admin_set_subscription` (pre-ledger) |
| `DOMAIN_AND_BILLING.md` | Manual MoMo runbook |
| **`018_subscription_billing_audit.sql`** | Payment ledger + stats + preferred activation |
| Pack migrations 014–017 | Parallel pack billing (already audited) |

**Run order:** 014 → 015 → 016 → 017 → **018**.
