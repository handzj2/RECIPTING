# HandzJ — Revised Pricing (Admin-Controllable)

## Starting pack list (live in catalog after migration 015)

| Code | Name | Credits | Price (UGX) | Per receipt | Notes |
|------|------|---------|-------------|-------------|-------|
| FREE_5 | 5 Free Receipts | 5 | 0 | — | Auto-grant on signup (optional) |
| **ENTRY_10** | **10 Digital Receipts** | **10** | **5,000** | **500** | **New low-entry pack** |
| STARTER_20 | 20 Digital Receipts | 20 | 10,000 | 500 | |
| GROW_50 | 50 Digital Receipts | 50 | 20,000 | 400 | |
| BUSINESS_100 | 100 Digital Receipts | 100 | 35,000 | 350 | |
| PRO_250 | 250 Digital Receipts | 250 | 75,000 | 300 | |
| SCALE_500 | 500 Digital Receipts | 500 | 125,000 | 250 | |
| ENTERPRISE_1000 | 1,000 Digital Receipts | 1,000 | 200,000 | 200 | |

**Monthly subscription (unchanged):** UGX 50,000 / month or UGX 500,000 / year.

---

## What you can do as platform admin (from the dashboard)

### 1. Adjust pricing live
- Change name, credits, price (UGX), sort order, active/inactive for any pack
- Create brand-new packs (e.g. “15 receipts for UGX 7,500”)
- Disable a pack without deleting history

### 2. Activate packs after Mobile Money
- Enter business UUID + choose pack + paste MoMo reference
- Credits appear on the merchant’s account immediately

### 3. Grant free / promo credits
- Give any number of credits to a business (goodwill, support, promo)

### 4. Monitor
- Packs sold (all-time + last 30 days)
- Revenue in UGX (all-time + 30 days)
- Credits granted vs consumed vs still held
- Number of customers who have bought packs
- Full purchase history with remaining balance per business

---

## Why UGX 5,000 entry pack

- Low enough for a small shop to try without feeling the UGX 50,000/month commitment
- Same effective rate as the 20-pack (UGX 500/receipt)
- Creates a clear ladder: 5 free → 10 for 5k → 20 for 10k → 50 for 20k → subscription

You can change any of these numbers at any time from the admin UI. No code deploy required for price changes.

---

## Files to run / use

| File | Action |
|------|--------|
| `014_receipt_packs_ledger.sql` | Run first (ledger + consumption rules) |
| `015_admin_pack_control.sql` | Run second (admin RPCs + ENTRY_10 pack) |
| `ADMIN_PACKS_UI_SECTION.html` | Paste HTML + JS into `public/admin.html` |
| `PRICING_PAGE_COPY.md` | Update public pricing page (add ENTRY_10) |

After both SQL migrations, open `/admin.html` as platform admin → you will see **Receipt pack pricing** and **Pack sales & credits** cards.
