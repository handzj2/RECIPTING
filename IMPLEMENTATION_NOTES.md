# HandzJ Digital Receipts — implementation notes (this pass)

## What shipped

### 1. Human-readable auth errors (§4)
- `login.html`: replaced `friendly()` with the fuller `humanAuthError()` mapper from the brief (length, already registered, email not confirmed, invalid credentials, rate limit, expired OTP, invalid email, network).
- All existing call sites still work via the `friendly` alias.

### 2. Interactive password rules (§3)
- Signup form now shows live rule list: ≥8 chars, lowercase, uppercase, number.
- Confirm-password match indicator.
- Create button stays disabled until rules pass, passwords match, email looks valid, and business name is present.
- Sign-in form is **not** constrained (existing short passwords still work).

### 3. Per-client receipt layout (§1)
- New migration: `sql/004_receipt_layout.sql`
  - `alter table businesses add column if not exists receipt_layout jsonb`
  - Updates `admin_list_businesses()` so the theme is returned for the admin badge.
- Renderer (`receiptHTML` in `app.html`) now:
  - Reads `biz.receipt_layout` via `resolveLayout()`
  - Supports themes: `classic` (default, unchanged look), `modern` (Inter, left-friendly), `thermal` (narrow monospace, no logo/watermark/stamp)
  - Honors `show.logo`, `show.tagline`, `show.whatsapp`, etc.
  - Supports `labels.title`, `labels.footer`, and sanitized `custom_css`
- Settings → **Receipt layout** card:
  - Preset buttons: Classic / Modern / Thermal
  - Advanced JSON editor with validation + CSS sanitization
- Admin table shows a small theme badge next to each business name.

### 4. Post-generation share CTA (§2)
- After a successful issue (and when opening a VALID receipt from the log), a **Send to customer** bar appears:
  - WhatsApp (wa.me, Uganda `0…` → `256…` normalization)
  - Email (mailto)
  - Native Share… (when `navigator.share` exists)
  - Copy link (clipboard of the short receipt message + verify URL)
- Hidden for trial-expired tenants and for VOIDED receipts.
- Existing view-tab WhatsApp / Email buttons remain as before.

## What you must run in Supabase

Open the SQL Editor and run:

```sql
-- from sql/004_receipt_layout.sql
```

(or paste the file contents). Safe to re-run.

No data backfill is required. Existing businesses keep `receipt_layout = null` → classic rendering (regression test #1).

## File map (actual repo layout)

```
public/
  app.html      # main app + receipt renderer + share bar + settings presets
  login.html    # auth + password rules + humanAuthError
  admin.html    # theme badge on business rows
  config.js
  index.html
  logo.jpg
sql/
  002_auth_multitenant.sql
  003_admin_dashboard.sql
  004_receipt_layout.sql   ← NEW
  supabase_schema.sql
```

There is no separate `app.js` / `receipt.js` / `styles.css` / `verify.html` — logic lives inside the HTML files (hash-route verify is inside `app.html`).

## Quick acceptance checklist

1. **Errors**: signup with a taken email → friendly message, no raw Supabase text.
2. **Password UI**: type “abc” → only some rules green; submit disabled; full rules + match → enabled.
3. **Layout**: new business with null layout looks identical to before. Set Modern → left-ish Inter styling. Set Thermal → narrow, no logo.
4. **Share**: issue a receipt → share bar appears; WhatsApp opens with verify link; Copy works.
5. **Admin**: after migration, theme badge shows (classic by default).

## Out of scope (unchanged)

Billing webhooks, custom domains, multi-user per business, freeform HTML templates.

---

## Phase 4 (product identity) — summary

See **PHASE4_REPORT.md** for the full design rationale.

Shipped in this pass:
- App chrome and navigation reframed around Issue / Register / Business
- Issue screen as document desk (form + preview)
- Receipt Register as table-first operational centre
- Verification page redesigned as document identity
- Marketing site demonstrates the product (sample receipt + verification)
- Visual system tightened: no gradients, reduced radius, document hierarchy
- Conceptual module map documented; no framework rewrite

Acceptance:
1. Open app.html → see “Issue Receipt · Receipt Register · Business”
2. Issue tab shows form + preview side-by-side on desktop
3. Register is a clean table (Date, Receipt, Customer, Amount, Status)
4. verify.html?no=… shows large VALID/VOIDED mark and structured record
5. Landing page shows sample receipt + verification card, not generic SaaS hero
