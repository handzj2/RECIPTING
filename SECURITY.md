# Security implementation (HandzJ Digital Receipts)

## Applied in codebase (this pass)

### HTTP / Vercel (`vercel.json`)
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY` (clickjacking)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy`: camera/mic/geo/payment disabled
- `Cross-Origin-Opener-Policy: same-origin`
- **Content-Security-Policy** (moderate — allows required CDNs + inline scripts used by the static app)
- `config.js` served with `Cache-Control: no-store`

### Verification IDs (`app.html`)
- `randId()` now maps **full random bytes → hex** (not `byte % 16`)
- New receipts use **32-character** `verifyId` (~128 bits)
- Client-side **800ms throttle** on `verify_receipt` RPC calls

### Database (`sql/022_security_hardening_p0.sql`)
- `verify_receipt` rejects missing/short `verify_id` (< 8 chars)
- Optional `verify_attempt_log` table for future abuse monitoring
- **Run this migration in Supabase SQL Editor**

## Still required (ops / Supabase dashboard — not pure code)

| Item | Action |
|------|--------|
| MFA | Enable Supabase Auth MFA; require for platform admin |
| Service role key | Never in `public/` or client env — server/Edge only |
| Rate limits | Supabase dashboard / Cloudflare in front of Vercel |
| WAF | Cloudflare proxy recommended for production domain |
| XSS continuous audit | Review any new `innerHTML` — always use `esc()` |
| Receipt content hash | Future: store SHA-256 of canonical payload at issue |

## Threat model (short)

- **Anon key is public.** Security = Auth + RLS + locked RPCs.
- **Issued receipts** are immutable except void via `void_receipt`.
- **Public verify** needs both receipt number and secret `verify_id`.
- **XSS** in tenant fields could target staff sessions — keep escaping strict.

## Deploy checklist

1. Deploy frontend (Vercel picks up `vercel.json` headers).
2. Run `sql/022_security_hardening_p0.sql` in Supabase.
3. Confirm Auth → MFA available; enroll admin accounts.
4. Rotate any key that was ever committed to git.
5. Hard-refresh and test: login, issue receipt, verify link, void.
