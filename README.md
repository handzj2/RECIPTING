# HandzJ Digital Receipts — Commercial Web System

Online receipt product for businesses that need to **generate, send, and verify** professional digital receipts.

## Quick start (local)

**Windows:** double-click `start.bat`

Then open:

- Landing (CTA): http://localhost:3000/
- Sign in / sign up: http://localhost:3000/login.html
- Owner dashboard: http://localhost:3000/admin.html (platform owner only)
- Receipt app: http://localhost:3000/app.html (redirects to login when signed out)

## Features

- **Multi-client SaaS**: each business signs up with email + password and gets its own isolated data
- **5-day free trial** per signup, enforced in the database — then a subscribe prompt
- **Per-tenant branding**: each business sets its own name, tagline, contacts, logo and receipt prefix in Settings
- **Owner dashboard** at `/admin.html`: every subscriber, trial countdowns, usage, one-click activation
- Branded digital receipts + logo
- Issue / void / search log
- PDF + QR verification
- **Send to client via WhatsApp**
- **Send to client via Email**
- Landing page with call-to-action and pricing
- Ready for **Supabase** (shared DB) + **Vercel** (hosting)

## Deploy to Vercel

```bash
cd handzj_receipt_saas
npx vercel login
npx vercel --prod
```

Or import the folder on [vercel.com](https://vercel.com).

## Connect Supabase (cloud log)

1. Create a project at [supabase.com](https://supabase.com)  
2. SQL Editor → run `sql/supabase_schema.sql`  
3. Copy URL + anon key into `.env.local` (see `.env.example`)  
4. SQL Editor → run `sql/002_auth_multitenant.sql` (accounts, isolation, trial)
   then `sql/003_admin_dashboard.sql` (owner dashboard — edit the admin email at the bottom)
5. Edit `public/config.js` with URL + anon key (see `docs/SUPABASE_SETUP.md`)
6. Follow `docs/AUTH_AND_TRIAL_SETUP.md` to enable email auth and claim your existing data

## Security model (read this before onboarding paying clients)

The anon key in `config.js` is public by design. Access is controlled by Supabase Auth
plus row level security: a signed-in business can only ever read and write rows where
`business_id` matches its own, and anonymous visitors can read **nothing** directly —
customer verification goes through a locked-down `verify_receipt()` function that needs
both the receipt number and its verification ID and returns masked fields only.

**Binding product rules** (immutability, void-only correction, verification claims,
audit trail, document states) are defined in:

→ **`docs/DOCUMENT_SECURITY_STANDARDS.md`**

Technical setup details remain in `docs/AUTH_AND_TRIAL_SETUP.md`.

## Email automation (optional)

Use [Resend](https://resend.com) with `RESEND_API_KEY` in `.env` to email PDF receipts automatically (API route on Vercel).

## Commercial docs

See `docs/COMMERCIAL_PLAN.md` for target clients, pricing template, and sales CTA.

## Project layout

```
handzj_receipt_saas/
├── start.bat                 # Local start + data folders
├── public/
│   ├── index.html            # Landing + CTA
│   ├── app.html              # Receipt system
│   └── logo.jpg
├── sql/supabase_schema.sql   # Multi-business cloud schema
├── docs/COMMERCIAL_PLAN.md
├── .env.example
├── vercel.json
└── README.md
```


## Supabase cloud sync

Configured via `public/config.js`. Full steps: `docs/SUPABASE_SETUP.md`.

When keys are set, issue/void/log use the cloud database. localStorage stays as an offline mirror.
