# HandzJ Receipt Packs — Unit Economics (Free → Paid Supabase)

All figures in UGX unless noted. Exchange rate used for planning: **1 USD ≈ UGX 3,500**.

---

## 1. Current state (Supabase Free)

| Cost item                    | Monthly cost |
|-----------------------------|--------------|
| Supabase                    | 0            |
| Vercel (Hobby)              | 0            |
| Receipt PNG generation      | ~0 (browser) |
| Domain (if any)             | 0 – 30,000   |
| Payment collection friction | manual       |
| **Total fixed**             | **≈ 0 – 50,000** |

Marginal cost per issued receipt on Free is negligible.  
We still use a **planning buffer of UGX 20–35 per receipt** so pricing remains safe when you leave Free.

---

## 2. Future paid plans (realistic Ugandan SaaS path)

### Supabase pricing (approximate, public list prices)

| Plan       | Approx. USD/mo | ≈ UGX/mo   | Typical limits (simplified) |
|------------|----------------|------------|-----------------------------|
| Free       | $0             | 0          | 500 MB DB, 1 GB storage, limited bandwidth |
| Pro        | $25            | 87,500     | 8 GB DB, 100 GB storage, better bandwidth |
| Team       | $599           | 2,096,500  | Higher limits + more seats  |

Most HandzJ-scale businesses will live comfortably on **Pro** for a long time.

### Other fixed costs once commercial

| Item                    | Monthly estimate (UGX) |
|-------------------------|------------------------|
| Supabase Pro            | 87,500                 |
| Vercel Pro (if needed)  | 70,000                 |
| Custom domain + DNS     | 5,000 – 15,000         |
| Support / admin time    | 50,000 – 150,000       |
| Monitoring / backups    | 10,000 – 30,000        |
| **Total fixed (mid)**   | **≈ 250,000 – 350,000**|

---

## 3. Marginal cost model (paid era)

Even on Pro we keep a conservative **infrastructure allowance of UGX 25–50 per issued receipt**.  
This covers:

- Postgres row + indexes
- Several verification / history queries
- Auth activity
- Bandwidth / egress
- Future image storage if you ever store PNGs
- Headroom for fair-use spikes

| Pack size | Credits | Planning allowance (UGX) | Selling price | Contribution after allowance |
|-----------|---------|---------------------------|---------------|------------------------------|
| 20        | 20      | 500 – 1,000               | 10,000        | 9,000 – 9,500                |
| 50        | 50      | 1,250 – 2,500             | 20,000        | 17,500 – 18,750              |
| 100       | 100     | 2,500 – 5,000             | 35,000        | 30,000 – 32,500              |
| 250       | 250     | 6,250 – 12,500            | 75,000        | 62,500 – 68,750              |
| 500       | 500     | 12,500 – 25,000           | 125,000       | 100,000 – 112,500            |
| 1,000     | 1,000   | 25,000 – 50,000           | 200,000       | 150,000 – 175,000            |

**Gross margin on packs remains excellent** (85–95% after the infrastructure buffer).

---

## 4. Break-even under paid Supabase

Assume mid-range fixed costs of **UGX 300,000 / month** (Supabase Pro + Vercel + light ops).

Using an average contribution of **≈ UGX 350 per credit** after the planning buffer:

| Metric                              | Value                          |
|-------------------------------------|--------------------------------|
| Fixed cost to cover                 | 300,000 UGX/mo                 |
| Credits needed to break even        | ≈ 860 credits/month            |
| Equivalent 50-credit packs          | ≈ 17 packs/month               |
| Equivalent 100-credit packs         | ≈ 9 packs/month                |
| Or mix of packs + 1–2 subscriptions | easily covers                  |

### Scenario table

| Paying customers (mix)              | Approx. monthly revenue | Covers UGX 300k fixed? | Notes |
|-------------------------------------|--------------------------|------------------------|-------|
| 10 × 20-packs                       | 100,000                  | No                     | Early stage |
| 15 × 50-packs                       | 300,000                  | Yes (bare)             | Break-even |
| 10 × 50-packs + 5 × 100-packs       | 375,000                  | Yes                    | Comfortable |
| 20 × 50-packs                       | 400,000                  | Yes                    | Healthy |
| 5 monthly subscriptions (50k)       | 250,000                  | Almost                 | Add a few packs |
| 8 monthly + 10 × 50-packs           | 600,000                  | Strong                 | Good margin |

---

## 5. Recommended pricing remains unchanged

The pack prices already leave large headroom even after moving to Supabase Pro:

| Pack              | Price     | Safe even on Pro? |
|-------------------|-----------|-------------------|
| 20                | 10,000    | Yes               |
| 50                | 20,000    | Yes               |
| 100               | 35,000    | Yes               |
| 250               | 75,000    | Yes               |
| 500               | 125,000   | Yes               |
| 1,000             | 200,000   | Yes               |
| Monthly sub       | 50,000    | Yes               |
| Annual sub        | 500,000   | Yes               |

You do **not** need to raise pack prices when you leave Free.  
The current list is commercially sound for both Free and Pro eras.

---

## 6. When to leave Supabase Free

Monitor these in the Supabase dashboard:

- Database size
- Bandwidth / egress
- Auth MAUs
- Storage (if you ever store images)
- Concurrent connections

**Practical trigger:** when you approach 60–70 % of any Free limit, or when you have 30+ active businesses, move to Pro. Do it proactively — do not wait for an outage.

---

## 7. Unit economics dashboard metrics (track monthly)

| Metric                        | Why it matters |
|-------------------------------|----------------|
| Packs sold by size            | Product-market fit |
| Credits purchased             | Top of funnel revenue |
| Credits consumed              | Actual usage |
| Credits remaining (liability) | Balance sheet view |
| Average revenue per credit    | Pricing power |
| Active subscriptions          | Recurring base |
| Supabase + Vercel cost        | Real infrastructure |
| Contribution after infra      | True gross margin |
| Support tickets / customer    | Hidden cost |

---

## 8. Bottom line

- On **Free**: almost pure contribution. Pack model is highly attractive for small Ugandan businesses.
- On **Pro (~UGX 87k)**: still excellent margins. Break-even is reachable with roughly 15–20 small pack buyers or a handful of monthly subscribers.
- The recommended pack prices (10k / 20k / 35k / 75k / 125k / 200k) are sustainable under both regimes.
- Keep the monthly subscription as the upgrade path for continuous issuers.
- Implement the ledger (migration 014) so every credit is auditable.

No price changes required when you upgrade Supabase. Focus on acquisition and clean credit accounting.
