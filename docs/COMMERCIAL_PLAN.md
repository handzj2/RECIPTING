# HandzJ Digital Receipts — Commercial plan

## Product

**Online digital receipt system** for businesses that collect money but have no proper receipting tool.

### Call to action (CTA)

> Stop sending payment screenshots.  
> Issue real digital receipts — generate, send on WhatsApp/Email, verify online.

Primary button: **Start issuing receipts** → `/app.html`

---

## Target clients

| Segment | Pain |
|---------|------|
| Retail / wholesale shops | Paper books, no search, no client copy |
| Software & license sellers | Need professional payment proof |
| Freelancers & agencies | Chat photos look unprofessional |
| Clinics, schools, NGOs | Donors/parents need formal receipts |
| Any SME in Uganda & region | No affordable receipt SaaS |

---

## Product tiers

| Plan | Price (template) | Includes |
|------|------------------|----------|
| **Starter** | Free (local) | Browser storage, PDF, WhatsApp share, logo |
| **Business** | e.g. UGX 50,000/mo | Supabase cloud log, team access, email send, online verify |
| **Enterprise** | Custom | Multi-branch, API, custom domain, onboarding |

Adjust pricing for your market.

---

## Roadmap

### Phase 1 — Now (this package)
- Landing page with CTA
- Web receipt app (generate, log, void, PDF, QR)
- **Send WhatsApp** / **Send Email** to client
- `start.bat` for local use
- Vercel static deploy
- Supabase SQL schema prepared

### Phase 2 — Cloud
- Connect Supabase (shared receipt log + verify from any phone)
- Deploy on Vercel production domain
- Optional Resend API for automatic email with PDF attachment

### Phase 3 — SaaS commercial
- Business signup / login
- Each business = tenant (own logo, receipts, clients)
- Billing (Mobile Money / card)
- Admin dashboard for HandzJ

---

## Local → Supabase → Vercel

```
1. start.bat          → try product locally
2. Create Supabase    → run sql/supabase_schema.sql
3. Fill .env.local    → URL + anon key
4. npx vercel --prod  → live commercial site
```

---

## Sales script (short)

1. “Do your clients still get payment proof as a WhatsApp photo?”  
2. “We issue branded digital receipts with a number and verification link.”  
3. “You generate in 30 seconds and send on WhatsApp or email.”  
4. “Start free locally; upgrade when you need cloud + team access.”

Contact: handzj2@gmail.com · 0781 909 507 · WhatsApp 0757 632 884
