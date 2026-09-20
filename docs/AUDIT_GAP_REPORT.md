# Evidence-based gap report — HandzJ Digital Receipts

**Inspected:** RECIPTING public/*.html, sql/*.sql, docs/*  
**Method:** Code vs documentation vs security model (no production DB available)  
**Date:** 2026-09-20

---

## A. Gap table (evidence-based)

| Area | Document says | Code actually does | Gap | Risk | Proposed fix |
|------|---------------|--------------------|-----|------|--------------|
| Tenant isolation (business) | RLS on business_id | `rcp_*` / `biz_*` policies use `my_business_id()` | Mostly OK after 002+008 | Low if 002 applied | Keep; harden my_business_id via memberships |
| Branch isolation | Cashier scoped to branch | RLS only checks `business_id`, not `branch_id` | **Cashiers can SELECT/INSERT any branch in tenant** by setting `branch_id` in JS | **P0** | RLS + insert checks on branch membership |
| Void authorization | Owner/manager only | `void_receipt` checks `can_void()`; **but** `rcp_owner_update` allows any member to UPDATE | Cashier can attempt direct UPDATE to VOIDED | **P0** | Drop client UPDATE policy; void only via RPC |
| Receipt immutability | Issued fields locked | Trigger in 005 blocks most field changes on UPDATE | OK if 005 applied; `lines`/`branch_id`/`issued_by` not listed in trigger | **P1** | Extend immutability columns |
| Numbering scope | (ambiguous) | `receipt_sequences (business_id, year)` — **business-wide** | Not branch-wide | Doc only | Document as intentional |
| Sequence races | Safe allocation | `ON CONFLICT DO UPDATE seq+1` in `next_receipt_no` | Good under concurrent inserts | Low | Optional advisory lock later |
| verify_id | Unpredictable secret | `randId(10)` hex from crypto getRandomValues | ~40 bits entropy — acceptable, not ideal | **P2** | Prefer 16+ chars |
| Public verify | Masked via RPC only | `verify_receipt` security definer; no anon table SELECT | OK | Low | Keep |
| Public fields | Limited | Returns amount, item, business contact, masked customer | Phone/email of customer not returned — OK; business email/phone exposed intentionally | Low | Optional tighten |
| Trial enforce | DB blocks issue | `business_active` on insert policy + `next_receipt_no` | OK | Low | Keep |
| Staff invite | Email must exist | `invite_staff` raises if no auth.users row | Matches docs | P3 UX | Document; optional invite-link later |
| Platform admin | Server-side | `platform_admins` + `is_platform_admin()` RPC | **Not** frontend-only | Low | Keep |
| Multi-shop UX | Owner sees all shops | Branches listed in settings; **no active shop selector** on issue/log | UX gap | **P2** | Branch selector for owner/manager |
| Historical branding | — | View uses **current** `CO` / logo, not snapshot at issue | Design gap | P3 | Snapshot optional later |
| Double Issue click | — | Button disabled during issue | Partial; no server idempotency key | **P1** | Keep disable + ignore re-entry flag |
| Cross-business branch | — | FK branch→business exists; **no CHECK** receipt.branch belongs to receipt.business | Possible bad row if client sends foreign branch UUID | **P1** | Trigger/constraint |
| Amount trust | — | Amount from browser sum of lines | Client can under/overstate | **P2** | Optional issue RPC validates sum |

---

## B. Security findings (priority)

### P0 — Must fix before production

1. **Client UPDATE on receipts**  
   Evidence: `002` policy `rcp_owner_update` for all authenticated members of the business.  
   `void_receipt` enforces role, but direct `supabase.from('receipts').update(...)` does not.  
   Immutability trigger may still block amount edits, but void metadata path can allow status→VOIDED without `can_void()`.

2. **No branch-scoped RLS**  
   Evidence: `rcp_owner_select` / `insert` only `business_id = my_business_id()`.  
   Membership `branch_id` is unused in policies.

### P1 — Core correctness

3. Immutability trigger missing newer columns (`lines`, `branch_id`, `issued_by`, `issued_by_name`).  
4. No DB guarantee that `receipts.branch_id` belongs to `receipts.business_id`.  
5. Double-submit only partially handled in UI.  
6. Numbering is **business-wide** (document clearly; do not silently switch to branch-wide).

### P2 — Reliability / UX

7. Owner/manager lack a primary **shop selector** on New / Log.  
8. verify_id length 10 hex — strengthen to 16.  
9. No server-side line-total validation.

### P3 — Later

10. Historical branding snapshot.  
11. Soft invite (email before signup).  
12. Full audit of settings changes.

---

## C. Data-model findings

| Constraint | Present? |
|------------|----------|
| unique (business_id, receipt_no) | Yes |
| verify_id indexed | Yes (not unique globally — OK with composite lookup) |
| membership unique (business_id, user_id) | Yes (008) |
| receipt.branch ∈ business | **No** |
| Numbering business-wide | **Yes** |

---

## D. UX findings

- Mobile line items + thermal formats exist.  
- Guided signup exists.  
- Missing: active branch chip/selector for multi-shop owners.  
- Staff invite requires prior signup (documented; friction for cashiers).

---

## E–J. Implemented in this pass

See `009_security_hardening.sql` + app.html changes below.

---

## E. Exact changes made

### SQL `009_security_hardening.sql`

1. **Dropped** `rcp_owner_update` — clients cannot UPDATE receipts; void only via `void_receipt`.
2. **Replaced** select/insert policies with branch-aware `rcp_member_select` / `rcp_member_insert`.
3. **Trigger** `receipts_branch_guard` — branch must belong to receipt’s business.
4. **Extended** immutability guard for `lines`, `branch_id`, `issued_by`, `issued_by_name`, `business_id`.
5. **Trigger** `receipts_stamp_issuer` — forces `business_id` from membership; stamps issuer.
6. **Re-asserted** `void_receipt` role check + audit event best-effort.

### `app.html`

1. `verifyId` length **16** (was 10).
2. `_issuingLock` prevents double Issue clicks.
3. **Shop/branch selector** on New Receipt; cashiers locked to assigned branch.

---

## F. New migrations

- `sql/009_security_hardening.sql` (run after 008)

---

## G. Tests (logic / code review — no live Supabase in this environment)

| Test | Expected | Result (by design) |
|------|----------|-------------------|
| Tenant A cannot read B | RLS business_id | Unchanged, still enforced |
| Cashier branch A cannot insert branch B | insert WITH CHECK | **Fixed in 009** |
| Cashier direct UPDATE void | No UPDATE policy | **Fixed in 009** |
| Cashier void RPC | can_void false | Already in 008/009 |
| Sequence concurrent | ON CONFLICT seq+1 | Unchanged, business-wide |
| Trial expired issue | business_active | Unchanged |
| verify invalid id | no row | Unchanged |

**Live verification required** after applying 009 on the project.

---

## H. Remaining issues

- Historical branding snapshot (P3)
- Server-side sum of line items (P2)
- Soft staff invite before signup (P3)
- Advisory lock on sequence under extreme concurrency (optional)
- Live penetration test with two real tenants

---

## I. Files changed

- `sql/009_security_hardening.sql` (new)
- `public/app.html` (lock, verify_id, branch UI)
- `docs/AUDIT_GAP_REPORT.md` (this report)

---

## J. Production-readiness blockers

1. **Must run** migrations through **009** on production Supabase.  
2. **Must re-test** with two accounts (owner + cashier on different branches).  
3. Confirm no client code path still calls `.update()` on `receipts` except void RPC.  
4. Platform admin row must exist in `platform_admins` for the real admin user.  

Until 009 is applied and live-tested, treat **branch isolation and client UPDATE** as open P0s in any deployed environment that only has 002–008.
