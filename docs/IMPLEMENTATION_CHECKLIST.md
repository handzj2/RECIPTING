# HandzJ Receipt Packs — Implementation Checklist

## 1. Database (do this first)

- [ ] Run `014_receipt_packs_ledger.sql` in Supabase SQL Editor
- [ ] Verify catalog rows exist:
  ```sql
  select code, name, credits, price_ugx from receipt_pack_catalog order by sort_order;
  ```
- [ ] Test `my_credit_summary()` and `my_receipt_credits()` as a logged-in merchant
- [ ] Optionally grant free credits after signup:
  ```sql
  select grant_free_starter_credits('<business_uuid>');
  ```

## 2. Admin activation flow

When a merchant pays via Mobile Money:

1. Merchant sends payment reference + login email
2. Admin opens admin dashboard (or runs SQL)
3. Call:
   ```sql
   select activate_receipt_pack(
     '<business_uuid>',
     'GROW_50',           -- or STARTER_20, BUSINESS_100, etc.
     'MTN-XXXXXX',        -- payment reference
     'mobile_money',
     'Activated by admin',
     24                   -- expires in 24 months (or null)
   );
   ```
4. Merchant refreshes app → credits appear

## 3. App changes (frontend)

- [ ] Show remaining credits in the main app header / issue screen
- [ ] Call `supabase.rpc('my_credit_summary')` on load
- [ ] When `credits_remaining === 0` and no active subscription → block “Issue receipt” and show “Buy a pack” CTA
- [ ] Display clear message: “1 credit = 1 successfully issued receipt”
- [ ] Never decrement credits client-side — the database trigger handles it

## 4. Pricing page

- [ ] Replace or extend `public/pricing.html` using the copy in `PRICING_PAGE_COPY.md`
- [ ] Keep both Packs and Monthly/Annual options visible
- [ ] Update meta description

## 5. Signup funnel (optional but recommended)

- [ ] After `signup_business` succeeds, call `grant_free_starter_credits(business_id)`
- [ ] Show “You have 5 free receipts” on first login

## 6. Monitoring

- [ ] Add a simple admin view of total credits sold vs consumed
- [ ] Watch Supabase Free limits weekly once you have >10 active businesses
- [ ] Plan the move to Supabase Pro when approaching 60–70 % of any Free limit

## 7. Commercial rules to decide once

| Decision | Recommendation |
|----------|----------------|
| Do credits expire monthly? | No |
| Long-stop expiry | 24 months of complete inactivity |
| Free starter size | 5 receipts |
| What consumes a credit? | Only successful INSERT of a VALID receipt |
| Subscription vs packs | Both live; subscription = unlimited while active |

## Files delivered

| File | Purpose |
|------|---------|
| `014_receipt_packs_ledger.sql` | Full migration — catalog, purchases, ledger, triggers, RLS |
| `PRICING_PAGE_COPY.md` | Ready-to-use marketing copy + UI outline |
| `UNIT_ECONOMICS_PAID_SUPABASE.md` | Cost model for Free and future Pro plans |
| `IMPLEMENTATION_CHECKLIST.md` | This file |
