# HandzJ Digital Receipts — Commercial Web System

Online receipt product for businesses that need to **generate, send, and verify** professional digital receipts.

## Quick start (local)

**Windows:** double-click `start.bat`

Then open:

- Landing (CTA): http://localhost:3000/
- Receipt app: http://localhost:3000/app.html

## Features

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
4. Edit `public/config.js` with URL + anon key (see `docs/SUPABASE_SETUP.md`)
5. Refresh the app — banner shows **Cloud sync ON**

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
