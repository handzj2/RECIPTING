# HandzJ Digital Receipts — Full System Workflows

**Product:** Multi-tenant online receipt system for shops and businesses  
**Stack:** Static web (HTML/JS) · Supabase (Auth + Postgres + RLS) · Vercel-ready  
**Last updated:** September 2026

---

## 1. What the system is

A commercial receipt platform where:

1. **Businesses** sign up, brand their receipts, and issue digital receipts.
2. **Workers** can issue/print under the owner’s account with limited rights.
3. **Customers** verify receipts online via link or QR.
4. **Platform owner** can see tenants, trials, and activation (admin).

It is **not** a shared “one database of all names.” Each business is isolated by `business_id` and login membership.

---

## 2. High-level architecture

```
                    ┌─────────────────┐
                    │  Vercel / static │
                    │  public/*.html   │
                    └────────┬────────┘
                             │ HTTPS
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
   index.html          login.html            app.html
   (landing CTA)       (auth + guided        (issue / log /
                        signup)               void / PDF /
                                              WhatsApp /
                                              settings)
         │                   │                   │
         │                   ▼                   ▼
         │            Supabase Auth        Supabase DB
         │            (email/password)     businesses
         │                                 memberships
         │                                 branches
         │                                 receipts
         │                                 sequences
         │
         └──────────► verify.html ──RPC──► verify_receipt()
                      (public, no login)
```

**Local run:** `start.bat` → http://localhost:3000  

**Config:** `public/config.js` → `SUPABASE_URL` + `SUPABASE_ANON_KEY`

---

## 3. Actors

| Actor | Entry | Main actions |
|-------|--------|----------------|
| **Visitor** | Landing | Sign up / Sign in CTA |
| **New business owner** | Signup wizard | Create account, trial, branding |
| **Owner** | App | Full control: issue, void, settings, staff, branches |
| **Manager** | App | Issue, void, some settings, branches |
| **Cashier** | App | Issue, print, WhatsApp/email — no void, no invite |
| **Customer** | Verify link/QR | See VALID/VOIDED + limited fields |
| **Platform admin** | admin.html | List businesses, trials, activate |

---

## 4. End-to-end workflows

### 4.1 Business signup (guided)

```
Landing → Sign up
  Step 1  Business name + type (retail, boutique, phones, electronics…)
  Step 2  Phone / WhatsApp (optional, validated if filled)
  Step 3  Email + strong password (live rule checks)
  → Supabase Auth signUp
  → If email confirm ON: check email → sign in
  → signup_business RPC → business row + 5-day trial
  → membership owner seeded (migration 008)
  → default branch "Main"
  → Redirect to app.html
```

**Checks that respond to the user**

- Business name too short → clear message  
- Password rules turn green/red live  
- Email format feedback  
- Phone length feedback  

---

### 4.2 Sign in

```
login.html → email + password
  → session
  → app loads business via:
       membership (staff)  OR  owner_id (owner)
  → load role, branches, staff list
  → Cloud sync ON
```

Staff who were invited sign in with **their** email and only see that business.

---

### 4.3 Issue a receipt

```
New receipt
  1. Customer name, phone, email (optional)
  2. Type: Goods | Service | Software
       (default from business type in Settings)
  3. Line items: name, qty, unit price → line total
       + Add line / remove line
       Amount = sum of lines (auto)
  4. Payment method, reference, date, received by, notes
  5. Preview (optional)
  6. Issue
       → next_receipt_no RPC (per business, per year)
       → INSERT receipt (immutable)
       → stamp issued_by, issued_by_name, branch_id
       → lines JSON (if column exists)
       → Show receipt + Share bar
       → Auto Download PDF (A4)
```

**Receipt number form:** `{PREFIX}-{YEAR}-{000001}`  
Example: `KPC-2026-000001`

**Trial:** If trial ended and not subscribed, issue is blocked in DB and UI.

---

### 4.4 Print & PDF

| Action | Format | Use |
|--------|--------|-----|
| **Download PDF** | A4 | Email, archive, WhatsApp file |
| **Print + Format A4** | A4 | Office printers |
| **Print + Thermal 80mm** | ~80mm roll | Most shop Bluetooth/USB thermal |
| **Print + Thermal 40mm** | ~40mm roll | Narrow/simple thermal |

Thermal layout: compact mono, less chrome; 40mm hides logo/QR/stamp.

**Bluetooth note:** Browser Print + Android print-service app is the practical path today. Direct Web Bluetooth is optional future (Chrome/Android only).

---

### 4.5 Send to customer

After issue (VALID only):

1. **WhatsApp** → prompt for number (e.g. 07… → 256…) → opens wa.me with message + verify link  
2. **Email** → mailto draft  
3. **Share…** → native share if available  
4. **Copy link** → clipboard  

No need to save the contact in the phone book.

---

### 4.6 Receipt log

```
Log tab
  → Search / filter VALID | VOIDED / date range
  → Click row → full receipt view
  → Download PDF / Print / Share / Void (if allowed)
```

---

### 4.7 Void (anti-fraud)

```
Owner or Manager only
  → Void + reason (required, min length)
  → void_receipt RPC
  → status = VOIDED, voided_at, void_reason
  → Number is NOT reused as a new VALID receipt
  → Verify page shows VOIDED
```

Cashiers do not see Void (UI + server).

---

### 4.8 Public verification

```
Customer scans QR or opens link:
  /verify.html?no=PREFIX-2026-000001&id=VERIFYID

  → RPC verify_receipt(no, id)
  → Needs BOTH numbers
  → Returns masked customer fields if valid
  → Shows VALID or VOIDED
  → No login; no full table access (RLS)
```

---

### 4.9 Branding (per tenant)

```
Settings → Business profile
  Name, tagline, phone, WhatsApp, email
  Receipt prefix
  Logo URL or file upload (data URL)
  Business type → drives default Goods/Service/Software labels
```

**Rule:** No platform (HandzJ) logo forced onto client receipts. Empty logo → initials placeholder.

---

### 4.10 Team & branches

```
Owner Settings → Team & branches
  Create branch (name, code)
  Invite staff:
    email must already have an Auth account
    role: cashier | manager
    optional branch
  Deactivate staff
```

**Isolation**

- Worker login ≠ owner login  
- `memberships` + RLS → only that `business_id`  
- Same display name on another signup = different tenant  

---

### 4.11 Platform admin

```
admin.html (platform owner email only)
  List businesses, trial status, usage
  Activate / manage subscription flags
```

---

## 5. Data model (core)

```
businesses
  id, owner_id, name, tagline, phone, whatsapp, email
  logo_url, prefix, category, receipt_layout
  trial_ends_at, subscription_status, subscribed_until

branches
  id, business_id, name, code, active

memberships
  id, business_id, user_id, role, branch_id
  display_name, invited_email, active

receipts
  id, business_id, branch_id
  receipt_no, verify_id, status
  kind, customer, contacts
  item, pkg, period, description, lines (jsonb)
  amount, currency, method, txn, paid_on
  received_by, notes
  issued_by, issued_by_name
  created_at, voided_at, void_reason

receipt_sequences
  business_id, year, seq
```

---

## 6. Security model

| Layer | Mechanism |
|-------|-----------|
| Auth | Supabase email/password |
| Tenant isolation | RLS on `business_id` / membership |
| Public reads | Blocked on tables; only `verify_receipt` RPC |
| Issue rights | Active trial or paid subscription (DB enforced) |
| Void rights | Owner/manager only |
| Immutability | Issued rows not client-updated; void via RPC |
| Anon key | Public in browser; safe because of RLS + Auth |

**Not prevented by name alone:** two “Kampala Phones” can exist. Access is never granted by matching names.

---

## 7. SQL migration order

Run in Supabase SQL Editor in order:

1. `supabase_schema.sql` — base tables  
2. `002_auth_multitenant.sql` — owner, trial, RLS, verify RPC  
3. `003_admin_dashboard.sql` — platform admin  
4. `004_receipt_layout.sql` — layout JSON  
5. `005_immutability_audit.sql` — audit / immutability  
6. `006_business_category.sql` — category column  
7. `007_receipt_lines.sql` — `lines jsonb`  
8. `008_staff_branches_roles.sql` — staff, branches, roles  

---

## 8. Page map

| Path | Purpose |
|------|---------|
| `/` | Landing, pricing CTA |
| `/login.html` | Sign in + 3-step signup |
| `/app.html` | Main product |
| `/verify.html` | Public verification |
| `/admin.html` | Platform owner dashboard |

---

## 9. Commercial flow (product)

```
Free trial (5 days) → Issue receipts freely
Trial ends → Can view/print old receipts; cannot issue new
Subscribe (manual/admin activate) → Issue again
```

Target users: shops without a receipt system — boutiques, phone shops, electronics, groceries, services.

---

## 10. Typical day in a shop

1. Cashier signs in on phone or counter tablet.  
2. New receipt → add line items → Issue.  
3. PDF downloads; share WhatsApp by typing customer number.  
4. Optional: Format **Thermal 80mm** → Print to Bluetooth printer (via OS print service).  
5. Customer later opens verify link → sees VALID.  
6. If mistake: Manager voids with reason; customer verify shows VOIDED.

---

## 11. Fraud response summary

| Threat | Response |
|--------|----------|
| Shared owner password | Train: invite staff instead |
| Cashier voids stock fraud | Role blocks void |
| Edited amount after issue | No client update of issued row |
| Photocopy VALID after void | Online verify shows VOIDED |
| Impersonate another shop | No access without their membership |
| Same name confusion | Names not unique keys; verify uses no+id |

---

## 12. File map

```
RECIPTING/
  public/
    index.html      landing
    login.html      auth + guided signup
    app.html        core app
    verify.html     public verify
    admin.html      platform admin
    config.js       Supabase keys
    logo.jpg        platform marketing logo only
  sql/              migrations 002–008 + base
  docs/
    SYSTEM_WORKFLOWS.md   ← this file
    STAFF_AND_BRANCHES.md
    SUPABASE_SETUP.md
    AUTH_AND_TRIAL_SETUP.md
    COMMERCIAL_PLAN.md
    DOCUMENT_SECURITY_STANDARDS.md
  start.bat
  vercel.json
```

---

## 13. Quick start checklist

1. Create Supabase project.  
2. Run SQL migrations 1→8.  
3. Put URL + anon key in `config.js`.  
4. `start.bat` or deploy to Vercel.  
5. Sign up as owner → Settings → logo & type.  
6. Issue test receipt → PDF + verify link.  
7. Optional: second user signup → owner invites as cashier.  

---

*This document describes the system as built through staff/branches/roles, multi-line items, thermal formats, PDF download, WhatsApp share, guided signup, and Supabase cloud sync.*
