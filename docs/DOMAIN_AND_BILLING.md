# Domain & billing runbook (commercial hardening)

## Production domain

| Item | Current | Required |
|------|---------|----------|
| Customer-facing origin | `https://recipting.vercel.app` | Custom domain e.g. `https://handzj.com` or `https://receipts.yourbrand.ug` |
| Config key | `window.HANDZJ_CONFIG.APP_URL` in `public/config.js` | Set to production origin **without trailing slash** |
| Verification URLs | Built as `APP_URL + /verify?no=&id=` | Must never point at localhost or preview deployments in production |

### DNS / Vercel steps
1. Buy domain.
2. Vercel → Project → Settings → Domains → add domain.
3. Point DNS (A/CNAME) as Vercel instructs.
4. Update `public/config.js` → `APP_URL: "https://your-domain"`.
5. Redeploy. Hard-refresh clients (Ctrl+F5).

### Verification rewrites (already in vercel.json)
- `/verify` → `verify.html`
- `/app/verify` and `/app/verify.html` → `verify.html` (legacy links)

## Manual Mobile Money activation (Phase 1)

```
Merchant chooses plan (UI)
  → Pays MTN/Airtel Money
  → Sends reference + login email to SUPPORT_CONTACT
  → Owner opens admin.html
  → Activates business (subscription_status = active, subscribed_until set)
  → Merchant issues again
```

No automatic MoMo API in this phase. Admin activation is authoritative.

## Trial rules (already enforced in DB)
- 5 days from signup (`trial_ends_at`)
- Writes blocked when not trialing and not active (`business_active()` / `TRIAL_EXPIRED`)
- Historical receipts remain readable after expiry
