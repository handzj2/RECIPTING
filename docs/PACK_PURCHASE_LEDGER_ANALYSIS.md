# Pack purchase ledgers — analysis

**Scope:** `receipt_pack_catalog` → `receipt_pack_purchases` → `receipt_credit_ledger`  
**Migrations:** 014 (core), 015 (admin), 016 (enforcement), 017 (audit)

---

## 1. Two-ledger design (intentional)

Pack commercial history and credit balance are **separate tables** on purpose:

```
CATALOG (what you sell)
    ↓
PURCHASES (what was bought / paid)     ← commercial / revenue ledger
    ↓
CREDIT LEDGER (what was granted / used) ← entitlement / balance ledger
    ↓
RECEIPT ISSUED (consumption of 1 credit)
```

| Table | Role | Mutable? |
|-------|------|----------|
| `receipt_pack_catalog` | Sellable products (price, credits, active) | Yes (admin) |
| `receipt_pack_purchases` | One row per pack activation / grant | Status can change; amounts are historical |
| `receipt_credit_ledger` | Running balance; every +/− | **Append-only** (no updates/deletes in design) |

**Why two tables?**

- A purchase is a commercial fact: money (or promo), pack code, MoMo ref, activator.
- Credits are an entitlement: they can be consumed gradually, adjusted, expired, or refunded.
- One purchase → one (or more) ledger `purchase` entries; many consumptions link back via `receipt_id`.

You can answer both:

- “How much revenue did GROW_50 generate?” → **purchases**
- “Why does this business have 17 credits left?” → **ledger**

---

## 2. Schema analysis

### 2.1 `receipt_pack_purchases`

| Column | Purpose | Notes |
|--------|---------|--------|
| `id` | PK | Linked from ledger as `purchase_id` |
| `business_id` | Tenant | Cascade delete with business |
| `catalog_id` | FK to catalog | Nullable if catalog row removed |
| `pack_code` | Denormalised code | Survives catalog edits/deletes |
| `credits_granted` | Credits at activation | Snapshot; not reduced as used |
| `price_ugx` | Amount charged | Snapshot of price at sale |
| `payment_ref` | MoMo / bank ref | Critical for disputes |
| `payment_method` | `mobile_money` \| `free` \| `admin` \| `promo` | |
| `status` | `pending` → `active` \| `expired` \| `cancelled` \| `refunded` | Default in insert path is `active` via activate fn |
| `activated_at` / `activated_by` | Who turned it on | Admin audit |
| `expires_at` | Long-stop (e.g. +24 months) | Optional; expiry job not automated yet |
| `notes` | Free text | |

**Strengths**

- Price and credits frozen at purchase time (catalog price changes do not rewrite history).
- `pack_code` denormalised → reports still work if catalog row is disabled/deleted.
- Payment ref supported (unlike pre-018 subscriptions).

**Weaknesses**

| Issue | Impact |
|-------|--------|
| No unique constraint on `payment_ref` | Same MoMo ref could activate twice |
| `pending` status exists but no first-class “create pending then activate” API | Pending rarely used in practice |
| No link from purchase to *how many credits still unused from this pack* | FIFO per-pack remaining not tracked (only global balance) |
| `on delete cascade` from business | Deleting a business wipes commercial history |

### 2.2 `receipt_credit_ledger`

| Column | Purpose |
|--------|---------|
| `entry_type` | `purchase` \| `consumption` \| `adjustment` \| `expiry` \| `refund` |
| `credits_delta` | +N or −1 (or −N for expiry/refund) |
| `balance_after` | Running balance after this entry |
| `purchase_id` | Set on grant entries |
| `receipt_id` | Set on consumption entries |
| `created_by` / `created_at` | Actor + time |

**Balance source of truth**

```sql
receipt_credits_remaining(biz) =
  latest balance_after ordered by created_at desc, id desc
```

Not a stored column on `businesses` — always derived from the ledger. That avoids drift between a cache column and the log.

**Integrity identity**

```
sum(credits_delta)  should equal  latest(balance_after)
remaining = purchased + adjustments − consumed − expired − refunded
```

Checked by `admin_credit_integrity` / `balance_ok` in `admin_business_credit_audit` (017).

---

## 3. Lifecycle (happy path)

```
1. Admin selects pack + business + MoMo ref
2. admin_activate_pack_for_business / activate_receipt_pack
3. INSERT receipt_pack_purchases (status=active, credits_granted=N, price_ugx=P)
4. INSERT receipt_credit_ledger (entry_type=purchase, delta=+N, balance_after=old+N)
5. Merchant issues receipt (VALID)
6. BEFORE INSERT: issuance_status must allow
7. AFTER INSERT: consume trigger
      - if subscription or trial → skip
      - else if remaining < 1 → raise NO_CREDITS
      - else INSERT ledger (consumption, delta=-1, balance_after=old-1)
```

**Free / promo path:** `grant_free_starter_credits` or `admin_grant_credits` → same purchase + ledger pattern (`FREE_5` / `ADMIN_GRANT`).

---

## 4. What the ledgers do *not* track

| Event | Tracked? |
|-------|----------|
| Pack purchase / activation | Yes — purchases + ledger |
| Credit consumption on issue | Yes — ledger + receipt_id |
| View / download / share / QR verify | **No** (by design) |
| Void receipt | **No** credit restore (by design — issue already consumed) |
| Per-pack FIFO remaining | **No** — only pooled balance |
| Failed issue attempts | **No** ledger row (good — no false consumption) |
| Catalog price at time of *quote* before pay | **No** — only at activation |

Void does **not** refund a credit. That is a product rule: the issuance already happened and is auditable on `receipts`.

---

## 5. Revenue vs entitlement views

### Revenue (commercial)

```sql
-- Pack revenue all-time / 30d
select * from admin_pack_stats();

-- Line items
select pack_code, price_ugx, payment_ref, activated_at, business_id
from receipt_pack_purchases
where status = 'active' and pack_code not in ('FREE_5','ADMIN_GRANT')
order by created_at desc;
```

### Entitlement (usage)

```sql
-- Platform feed
select * from admin_credit_usage_feed('consumption', 50);
select * from admin_credit_usage_feed('purchase', 50);

-- One business
select * from admin_credit_ledger('<biz_uuid>', 100);
select * from admin_credit_integrity('<biz_uuid>');
```

### Combined commercial (with subscriptions, after 018)

```sql
select * from admin_commercial_revenue_summary();
```

---

## 6. Risk analysis

| Risk | Likelihood | Mitigation today | Recommended |
|------|------------|------------------|-------------|
| Double activation with same MoMo ref | Medium | Process/discipline only | Unique partial index on `payment_ref` where not null |
| Concurrent issues at balance = 1 | Low–Medium | AFTER INSERT fails second | Optional advisory lock or serializable txn |
| Balance drift (manual SQL edits) | Low | `admin_credit_integrity` | Never UPDATE ledger rows; only append adjustments |
| Catalog price change rewrites history | None | Snapshots on purchase | Keep as-is |
| Orphan ledger if purchase deleted | Low | FK `on delete set null` | Prefer status=`cancelled`/`refunded` over DELETE |
| Expiry never runs | Medium | `expires_at` stored only | Cron: post `expiry` entries for packs past `expires_at` |
| Admin grant without note | Medium | Optional note | Require note in UI for grants |

---

## 7. Relationship to subscription billing

| Dimension | Packs | Subscriptions (post-018) |
|-----------|-------|---------------------------|
| Commercial table | `receipt_pack_purchases` | `subscription_payments` |
| Entitlement | Credit ledger balance | `subscribed_until` time window |
| Consumption | 1 credit / issue | Unlimited while active |
| Payment ref | Yes | Yes (018) |
| Stacking | Credits add to pool | Period extends from max(now, current end) |

When **subscription is active**, pack credits are **not** consumed (016).  
When subscription **expires**, remaining pack credits still allow issuance.

---

## 8. Operational query cookbook

```sql
-- Top packs by revenue
select pack_code,
       count(*) as sales,
       sum(price_ugx) as revenue_ugx,
       sum(credits_granted) as credits_sold
from receipt_pack_purchases
where status = 'active' and price_ugx > 0
group by pack_code
order by revenue_ugx desc;

-- Businesses with credits but no recent consumption (dormant liability)
select b.name, public.receipt_credits_remaining(b.id) as remaining
from businesses b
where public.receipt_credits_remaining(b.id) > 0
  and not exists (
    select 1 from receipt_credit_ledger l
    where l.business_id = b.id and l.entry_type = 'consumption'
      and l.created_at > now() - interval '60 days'
  );

-- Purchase without matching ledger purchase entry (should be empty)
select p.id, p.pack_code, p.business_id
from receipt_pack_purchases p
where p.status = 'active'
  and not exists (
    select 1 from receipt_credit_ledger l
    where l.purchase_id = p.id and l.entry_type = 'purchase'
  );

-- Consumptions without a valid receipt (should be empty)
select l.id, l.business_id, l.receipt_id
from receipt_credit_ledger l
where l.entry_type = 'consumption'
  and (l.receipt_id is null
       or not exists (select 1 from receipts r where r.id = l.receipt_id));
```

---

## 9. Verdict

| Aspect | Assessment |
|--------|------------|
| Separation of purchase vs credit ledger | **Sound** — correct commercial design |
| Running balance via `balance_after` | **Sound** — auditable, no cache column drift |
| Snapshot of price/credits at sale | **Sound** |
| Trace consumption → receipt | **Sound** |
| Trace grant → purchase | **Sound** |
| Payment ref on packs | **Sound** (ahead of old subscription path) |
| Duplicate payment_ref guard | **Missing** — add if abuse appears |
| Per-pack remaining (FIFO) | **Not needed** for current pooled product |
| Automated expiry | **Not implemented** — `expires_at` only |
| Append-only discipline | **By convention** — enforce with revoke of UPDATE/DELETE for non-service roles if desired |

**Overall:** The pack purchase + credit ledgers are fit for a manual-MoMo, credit-pack SaaS. They support revenue reporting, customer disputes (“I bought 100, used 83, have 17”), and integrity checks. Highest-value hardening left: unique `payment_ref`, automated expiry job, and admin UI that always requires a payment reference on paid activations.

---

## 10. Related files

| File | Role |
|------|------|
| `014_receipt_packs_ledger.sql` | Tables + activate + consume |
| `015_admin_pack_control.sql` | Admin activate / grant / list / stats |
| `016_usage_based_credit_limits.sql` | NO_CREDITS gates |
| `017_credit_usage_audit.sql` | Integrity + feeds + daily usage |
| `CREDIT_USAGE_AUDIT_REPORT.md` | Usage audit |
| `018_subscription_billing_audit.sql` | Parallel sub payment ledger |
