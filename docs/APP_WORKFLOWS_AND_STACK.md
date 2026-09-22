# HandzJ Digital Receipts — App workflows, framework & stack

**Product:** Digital receipt register for Ugandan (and regional) merchants  
**Primary surface:** Progressive web app (static HTML + Supabase backend)  
**Deploy target:** Vercel (`recipting.vercel.app`)

---

## 1. Technology stack

| Layer | Choice | Role |
|-------|--------|------|
| **Frontend** | Vanilla HTML / CSS / JS (no React/Vue build) | Fast load, zero build step, mobile-first |
| **Auth & DB** | Supabase (Postgres + Auth + RLS) | Multi-tenant businesses, receipts, credits |
| **Hosting** | Vercel | Static `public/` + rewrites (`vercel.json`) |
| **Payments** | Manual Mobile Money (MTN / Airtel) | Admin activates packs/subs with payment ref |
| **Phone parse** | libphonenumber-js (CDN, optional) | Uganda + international numbers |
| **Share** | `wa.me` links + optional Web Share API | Direct WhatsApp chat; native share secondary |
| **Images** | Client-side canvas / DOM snapshot | Receipt PNG for WhatsApp / download |

**SQL migrations:** `sql/002` … `sql/021` (run in order after base schema).

**Key runtime files**

| File | Purpose |
|------|---------|
| `public/app.html` | Merchant operating app (issue, register, WhatsApp) |
| `public/admin.html` | Platform owner: businesses, packs, MoMo activation |
| `public/login.html` | Sign in / sign up + trial |
| `public/pricing.html` | Packs + subscription pricing |
| `public/verify.html` | Public receipt verification |
| `public/config.js` | Supabase URL + anon key |

---

## 2. Multi-tenant model

```
auth.users (Supabase)
    └── businesses (owner_id, trial, subscription, KYC…)
            ├── receipts (immutable issue record + lines jsonb)
            ├── receipt_pack_purchases
            ├── receipt_credit_ledger
            └── subscription_payments
```

- **RLS** isolates data per business.
- **Platform admin** (`platform_admins` + `is_platform_admin()`) manages all tenants.

---

## 3. Core merchant workflows

### 3.1 Sign up → first receipt

```
1. /login.html?mode=signup
2. signup_business() → trial 5 days
3. grant_free_starter_credits() → 5 FREE_5 credits (migration 020)
4. /app.html → Issue form
5. Add lines (optional serial/IMEI) → Issue Receipt
6. next_receipt_no() + insert receipts
7. Credit consumed only if no active subscription/trial path allows free issue
```

**Issuance gates (`business_active` / `next_receipt_no`):**

| Condition | Can issue? |
|-----------|------------|
| Active subscription | Yes (unlimited; no credit burn) |
| Trial not ended | Yes |
| Credits remaining > 0 | Yes (1 credit per VALID issue) |
| Else | `NO_CREDITS` / locked |

### 3.2 Issue receipt (happy path)

```
Customer → Line items (name, qty, price, serial?, imei?)
         → Amount auto-sum
         → Payment method + date + received by
         → Issue
         → Permanent receipt_no + verify_id
         → Delivery bar: WhatsApp | PDF | Image | Print | Verify link
```

**Serial / IMEI (optional)**

- Serial: 4–64 chars, letters/digits/separators  
- IMEI: 15 digits + Luhn  
- Qty must be 1 when serial or IMEI is set  

### 3.3 WhatsApp send

```
1. User taps WhatsApp on issued receipt
2. Sheet: enter client number (required)
3. validate → normalizePhone (UG default)
4. Download receipt PNG (best effort)
5. Open https://wa.me/{digits}?text=…  ← direct chat, not Contacts
```

Missing/invalid number → field error + toast; **Open WhatsApp** disabled while empty.

### 3.4 Public verification

```
Customer opens /verify?no=… or scans QR
→ Lookup receipt by verify_id / receipt_no
→ Show VALID / VOIDED + merchant + amount + date
```

Does **not** consume credits.

### 3.5 Buy pack or subscribe (merchant)

```
1. Pay MoMo → keep transaction reference
2. Email/WhatsApp support with login email + ref + pack or plan
3. Admin: Activate payment tab → select business by name → paste ref → Activate
```

---

## 4. Admin workflows

| Tab | Job |
|-----|-----|
| **1. Businesses** | Search, filter, **Manage** drawer (KYC, trial, suspend, rename) |
| **2. Activate payment** | After MoMo: business name + payment ref → pack **or** subscription |
| **3. Pack prices** | Edit catalog (ENTRY_10 @ 5,000, etc.) |
| **4. Sales history** | Pack sales + credit stats |

**Rules**

- Paid pack/sub activation requires **payment_ref**  
- Paid packs: platform admin only  
- Unique payment_ref indexes (hardening 019)

---

## 5. Commercial model (summary)

| Product | Price (default) |
|---------|-----------------|
| Free on signup | 5 credits |
| Entry pack | 10 credits · UGX 5,000 |
| Starter → Enterprise | 20–1,000 credits · UGX 10k–200k |
| Monthly | UGX 50,000 |
| Annual | UGX 500,000 |

Credits ≠ storage rows. Entitlement ledger tracks remaining; receipts stay stored after use.

---

## 6. UI motion & guidance (living app)

| Element | Behaviour |
|---------|-----------|
| **Live strip / banner** | Continuous horizontal ticker (not a static image) |
| **Guide tip** | Rotates every ~7s with step tips (issue → serial → WA → credits) |
| **Primary buttons** | Soft hover lift + pulse on landing CTA |
| **Cards** | Entrance fade-up; hover lift on marketing cards |
| **Reduced motion** | All continuous animation disabled when OS requests it |

Files: `app.html` (strip + tips), `index.html` (landing ticker).

---

## 7. SQL migration map

| # | Name | Purpose |
|---|------|---------|
| 002–013 | Auth, admin, lines, RLS, KYC… | Base platform |
| 014 | Receipt packs + ledger | Entitlements |
| 015 | Admin pack control | Catalog RPCs |
| 016 | Usage-based credit limits | `NO_CREDITS` gates |
| 017 | Credit usage audit | Admin/merchant ledgers |
| 018 | Subscription billing audit | Payment ledger |
| 019 | Hardening | Unique refs, admin-only paid packs |
| 020 | Signup free credits | Auto FREE_5 + backfill |
| 021 | Serial / IMEI | Indexes + line shape docs |

Run **014 → 021** in order. For 016: `DROP FUNCTION my_credit_summary()` if return type changed.

---

## 8. End-to-end flow diagram

```
                    ┌─────────────┐
                    │   Signup    │
                    │ trial+5 cr  │
                    └──────┬──────┘
                           ▼
┌──────────┐  issue   ┌─────────────┐  wa.me   ┌──────────┐
│  Issue   │─────────►│  Register   │─────────►│ Customer │
│  form    │          │  + delivery │          │ WhatsApp │
└──────────┘          └──────┬──────┘          └────┬─────┘
                             │                      │
                             │ verify link          │ QR / link
                             ▼                      ▼
                      ┌─────────────┐        ┌─────────────┐
                      │  Supabase   │◄───────│  /verify    │
                      │  receipts   │        │  VALID page │
                      └──────┬──────┘        └─────────────┘
                             │
              credits / sub  │
                             ▼
                      ┌─────────────┐
                      │ Admin MoMo  │
                      │ activate    │
                      └─────────────┘
```

---

## 9. Security notes

- RLS on all tenant tables  
- Commercial tables: RPC-only writes for clients  
- Receipts effectively immutable after issue (void updates status)  
- Platform admin gated by `is_platform_admin()`  
- No automatic payment gateway — human confirms MoMo ref  

---

## 10. Operator checklist

1. Run SQL 014–021  
2. Deploy `public/`  
3. Confirm owner email in `platform_admins`  
4. Test: signup → 5 credits → issue → WhatsApp with number → verify URL  
5. Test admin: activate ENTRY_10 with a fake ref on a test business  

---

*Living UI + workflows documented for HandzJ Digital Receipts — 2026-09-22*
