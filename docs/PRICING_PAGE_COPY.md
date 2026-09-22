# HandzJ Digital Receipts — Pricing Page Copy & UI Structure

Use this content to update `public/pricing.html` (or build a new section).

---

## Page Title & Meta

**Title:** Pricing | HandzJ Digital Receipts  
**Meta description:** Buy digital receipt packs or subscribe monthly. No monthly commitment required for packs. 5 free receipts to start. Pay via Mobile Money.

---

## Hero / Lead

**Headline:**  
Only pay for the receipts you actually need

**Sub-headline:**  
Digital receipts without a monthly commitment.  
Buy a pack, use the credits whenever your business needs them. Credits do not expire every 30 days.

---

## Two Paths (side-by-side cards)

### Path 1 — Pay-as-you-go (Receipt Packs)

**Badge:** No monthly commitment

| Pack | Credits | Price | Effective / receipt |
|------|---------|-------|---------------------|
| Free | 5 | UGX 0 | — |
| Starter | 20 | UGX 10,000 | 500 |
| Grow | 50 | UGX 20,000 | 400 |
| Business | 100 | UGX 35,000 | 350 |
| Pro | 250 | UGX 75,000 | 300 |
| Scale | 500 | UGX 125,000 | 250 |
| Enterprise | 1,000 | UGX 200,000 | 200 |

**CTA button:** Buy a pack → (scrolls to “How to buy” or opens WhatsApp/email)

**Fine print under packs:**
- 1 credit = 1 successfully issued receipt
- Viewing, downloading, sharing or verifying a receipt does **not** use another credit
- Credits do not expire monthly (long-stop may apply after 24 months of inactivity)
- Existing receipts always remain viewable and verifiable

### Path 2 — Continuous use (Subscription)

**Badge:** Best for daily issuers

| Plan | Price |
|------|-------|
| Business Monthly | UGX 50,000 / month |
| Business Annual | UGX 500,000 / year (save 2 months) |

**Includes:**
- Unlimited* receipt issuance while subscription is active
- Cloud receipt register
- Online QR verification
- PDF + WhatsApp image
- Team / staff access (where enabled)

\*Fair-use applies. Contact us for very high volume.

**CTA button:** Subscribe → 

---

## How to buy a pack (step list)

1. Choose the pack size that matches your expected volume.
2. Pay via **MTN Mobile Money** or **Airtel Money**.
3. Send the payment reference + your login email to support (see Contact).
4. We activate the credits on your account — usually the same day.
5. Issue receipts. Your remaining balance is always visible in the app.

**Support contact:**  
handzj2@gmail.com · 0781 909 507 · WhatsApp 0757 632 884

---

## Free starter

Every new business receives **5 free digital receipts** after signup.  
No credit card. No Mobile Money required to try.

**CTA:** Start free → `/login.html?mode=signup`

---

## Comparison table (optional section)

| Feature | Free / Packs | Monthly Subscription |
|---------|--------------|----------------------|
| Monthly commitment | None | Yes |
| Credits expire every 30 days | No | N/A (unlimited while active) |
| Cost control for low volume | Excellent | Higher if you issue few receipts |
| Best for | Shops that issue 10–100 receipts/month | Businesses issuing every day |
| Online verification | Yes | Yes |
| WhatsApp / PDF | Yes | Yes |

---

## FAQ (short)

**Do unused credits expire at the end of the month?**  
No. Credits stay on your account until used (subject to a long-stop after prolonged inactivity).

**What uses one credit?**  
Only a successfully issued receipt. Opening, viewing, downloading, sharing or verifying the same receipt does not consume another credit.

**Can I still buy the monthly plan?**  
Yes. The monthly and annual plans remain available for businesses that prefer unlimited issuance.

**What happens to my old receipts if I only buy packs?**  
They remain fully viewable, printable and verifiable forever.

**How do I see my remaining balance?**  
Inside the app after login. You will also see it when you try to issue a new receipt.

---

## Upgrade path (visual funnel)

```
Try 5 free
    ↓
Need more → Buy 20 (UGX 10,000)
    ↓
Business grows → Buy 50 or 100
    ↓
Issuing every day → Switch to monthly subscription
```

---

## Legal / notes to keep

- Manual Mobile Money activation in the current release (no automatic gateway yet).
- Prices in UGX. Subject to change with notice.
- Receipt packs are a commercial entitlement to issue receipts; they are not a sale of database storage.
- See Terms of Service for full conditions.

---

## Suggested UI structure (HTML outline)

```html
<section class="pricing-hero">
  <h1>Only pay for the receipts you actually need</h1>
  <p class="lead">…</p>
</section>

<section class="two-paths">
  <div class="path packs">… pack cards …</div>
  <div class="path subscription">… monthly/annual cards …</div>
</section>

<section class="how-to-buy">… steps …</section>

<section class="free-starter">…</section>

<section class="faq">…</section>
```

Keep the existing dark theme, Barlow Condensed headings, and Inter body font for consistency with the rest of the site.
