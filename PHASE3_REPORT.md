# Phase 3 — Controlled repairs (complete)

**Scope:** immutability, clean verify URL, minimal audit, migration 004 readiness.  
**Out of scope:** UI redesign, new product features, billing engine.

---

## What changed

### 1. Receipt immutability (Postgres-enforced)

**File:** `sql/005_immutability_audit.sql`

| Mechanism | Behaviour |
|-----------|-----------|
| Trigger `trg_receipts_immutability` | On UPDATE: only VALID→VOIDED allowed, and only `status` / `voided_at` / `void_reason` may change. Any edit to amount, customer, item, dates, etc. raises `IMMUTABLE: …`. Voided rows are fully frozen. |
| RLS | Client **UPDATE policy removed**. Ordinary client `update`/`upsert` fails with RLS denial. |
| Issue path | Client uses **INSERT only** (`cloudSaveReceipt`). No upsert. |
| Void path | New RPC `void_receipt(p_receipt_no, p_reason)` — security definer; sets void fields and writes audit event. |

**Client (`app.html`)**
- `cloudSaveReceipt` → `insert` (not upsert)
- `confirmVoid` → `void_receipt` RPC
- Cache updated from RPC return value

### 2. Clean verification URL

| Before | After |
|--------|--------|
| `/app.html#/verify/HJT-2026-000421/{id}` | `/verify.html?no=HJT-2026-000421&id=…` |

- New page: `public/verify.html`
- Still uses **only** existing `verify_receipt()` RPC (no second engine)
- VALID / VOIDED / NOT FOUND states preserved
- Explicit disclaimer: not government/tax certification
- Old hash QR links **redirect** to `verify.html` (backward compatible)
- `verifyUrl()` in `app.html` now emits the clean URL (QR, WhatsApp, email, copy)

### 3. Minimal audit trail

**Table:** `receipt_events`

| Column | Purpose |
|--------|---------|
| `receipt_id`, `business_id`, `receipt_no` | Document reference |
| `event_type` | `ISSUED` \| `VOIDED` only |
| `actor_id`, `actor_email` | Who performed the action |
| `reason` | Void reason |
| `created_at` | Timestamp |

- ISSUED logged by trigger on insert  
- VOIDED logged inside `void_receipt`  
- Owners can SELECT their events; no client writes  

### 4. Migration 004 (`receipt_layout`)

- File remains: `sql/004_receipt_layout.sql`
- Safe `add column if not exists`
- Must be applied in Supabase if not already present
- Layout system not rewritten

---

## What you must run in Supabase SQL Editor

Run in order:

```text
1) sql/004_receipt_layout.sql     -- if not already applied
2) sql/005_immutability_audit.sql -- required for this phase
```

Both are idempotent (`if not exists` / `create or replace` / `drop … if exists`).

---

## Phase 5 test matrix (run after migrations)

### Happy path
1. Sign in → Issue receipt → number assigned (e.g. `HJT-2026-000xxx`)
2. Open receipt → QR / Copy link → URL is `/verify.html?no=…&id=…`
3. Open link (incognito) → **VERIFIED** / VALID, masked customer/ref
4. Void with reason → log shows VOIDED; verify page shows **VOIDED**
5. Old hash link `#/verify/…` → redirects to `verify.html`

### Immutability (critical)
6. In Supabase SQL (as service role or via client if possible), attempt:
   ```sql
   update receipts set amount = 1 where receipt_no = 'HJT-…' and status = 'VALID';
   ```
   → Must fail (`IMMUTABLE: …` or RLS denial)
7. Client cannot “re-save” an issued receipt with changed fields (insert unique conflict or no update path)
8. Second void of same receipt → rejected

### Audit
9. After issue: `select * from receipt_events where receipt_no = '…'` → one `ISSUED` row  
10. After void: second row `VOIDED` with reason and actor  

### Regression
11. Trial-expired tenant cannot issue (existing gate)  
12. Can still void after trial end (RPC is security definer; not blocked by insert policy)  
13. Existing VALID receipts still verify  
14. PDF / print still work  

---

## Files touched

```
sql/005_immutability_audit.sql   NEW
public/verify.html               NEW
public/app.html                  cloudSaveReceipt, cloudVoidReceipt, confirmVoid, verifyUrl, route redirect
sql/004_receipt_layout.sql       unchanged (confirm applied)
```

No UI redesign. No second receipt engine. No billing changes.

---

## Success criteria (from brief)

| Criterion | Status after Phase 3 |
|-----------|----------------------|
| Business issues permanent receipt | Yes |
| Customer verifies online from QR | Yes — clean URL |
| Platform shows VALID / VOIDED / NOT FOUND | Yes |
| Attempted edit of issued receipt rejected by DB | Yes — trigger + RLS |
| Void records actor + reason + timestamp | Yes — `receipt_events` |
| No parallel verification engine | Yes — same RPC |
| No UI redesign | Yes |

---

## Not done (correctly deferred)

- Phase 4 visual identity (issuing desk / register / verification terminal)
- Plan limits, automated billing, customer directory, staff roles
- Persisted DRAFT status
- Amount-specific search filter
