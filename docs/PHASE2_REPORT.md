# Phase 2 — Core UX & commercial usability

**Mode:** Controlled implementation (no architecture change, no security weaken, no new migration)

## A. Files inspected

- `public/app.html` (form, issue, log, view, trial, branch, share)
- `docs/SYSTEM_WORKFLOWS.md`, `AUDIT_GAP_REPORT.md`, `STAFF_AND_BRANCHES.md`
- SQL 008/009 (roles, branch RLS) — not modified

## B. Files changed

- `public/app.html`
- `docs/PHASE2_REPORT.md` (this file)

## C. Database changes

**None.** Phase 2 used existing schema only.

## D. Features implemented

1. **Fast cashier flow** — clearer Issue states; double-issue lock reset in `finally`; human-readable errors; optional customer (defaults to Walk-in).
2. **Post-issue banner** — number, amount, method, date, branch; actions: WhatsApp, Print, PDF, Copy verify, New receipt.
3. **Owner/manager shop scope** — “All shops” + per-branch filter on log (UX only; RLS still authoritative).
4. **Cashier branch lock** — scope select disabled when `staffBranchId` set.
5. **Ops dashboard on log** — today VALID count, total, voids, loaded count (from actual cache data).
6. **Search** — includes phone and amount text; status + date + branch filters.
7. **Trial messaging** — existing pill + clearer issue-blocked copy.
8. **Mobile** — full-width post-issue actions under 720px.

## E. Deliberately NOT implemented

- Inventory, accounting, CRM, payment gateway, AI
- Historical branding snapshot system
- DB idempotency keys for issue
- New migrations / new tables
- Framework rewrite

## F. Tests (code-level / logic)

| Test | Actor | Expected | Actual | Result |
|------|--------|----------|--------|--------|
| Customer empty | Cashier | Walk-in default | validate sets Walk-in | PASS (code) |
| Issue lock reset | Any | Second click after finish works | `_issuingLock = false` in finally | PASS (code) |
| Failed issue message | Any | Check log before retry | humanErr path | PASS (code) |
| Branch scope All | Owner | UX filter null | fBranchScope empty value | PASS (code) |
| Cashier cannot switch shop in UI | Cashier | select disabled | fillBranchScopeSelect | PASS (code) |
| Dashboard empty | New biz | Zeros not fake data | counts from cache | PASS (code) |
| Security RLS | — | Unchanged | No SQL changes | PASS |
| Verify URLs | Customer | Unchanged | verifyUrl untouched | PASS |

Live multi-user matrix still requires human run on deployed app.

## G. Security regression

- No policy/RPC changes.
- Branch selector does not set security; only filters client cache.
- Void still role-gated server-side (009).

## H. PDF/print

- Not structurally changed; still `downloadReceipt` / `printReceipt` + format select.
- Regression: manual A4 / 80mm / 40mm recommended after deploy.

## I. Mobile / a11y

- Post-issue buttons full width on small screens.
- Status still text VALID/VOIDED + class.
- Labels retained on new controls.

## J. Remaining issues

- Live verification of Phase 2 UI on phone.
- Double-network-retry idempotency still only UI-level.
- Legacy receipts with null `branchId` hidden when a specific shop is selected (shown under All shops).

## K. Recommended next controlled phase

- Soft staff invite (email before signup) **or**
- Optional server-side line-total check on issue **or**
- Historical branding snapshot (explicit migration design)
