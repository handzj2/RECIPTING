# Connect Supabase cloud sync

## 1. Create project

1. Go to https://supabase.com → New project  
2. Wait until the database is ready  

## 2. Run the schema

1. Supabase → **SQL Editor** → New query  
2. Paste contents of `sql/supabase_schema.sql`  
3. Click **Run**  

This creates:

- `businesses` (tenants)
- `receipts`
- `receipt_sequences`
- Seed row for HANDZJ TECH SOLUTIONS
- Open starter policies (tighten later with Auth)

## 3. Copy API keys

Supabase → **Project Settings** → **API**:

- Project URL → `SUPABASE_URL`
- `anon` `public` key → `SUPABASE_ANON_KEY`

## 4. Configure the app

Edit `public/config.js`:

```js
window.HANDZJ_CONFIG = {
  SUPABASE_URL: "https://xxxx.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOi...",
  BUSINESS_ID: "",          // optional; auto-detects HandzJ business
  APP_URL: "https://your-app.vercel.app"
};
```

## 5. Deploy / refresh

- Local: run `start.bat`, hard-refresh the browser  
- Vercel: redeploy after committing `config.js`  

When cloud is on, the app shows:

> Cloud sync **ON** (Supabase)…

## 6. What syncs

| Action | Cloud |
|--------|--------|
| Issue receipt | Inserted into `receipts` |
| Void receipt | Updated status + reason |
| Receipt log | Loaded from Supabase (all devices) |
| Receipt numbers | `receipt_sequences` per year |
| Offline | localStorage mirror kept as backup |

## 7. Security note

Starter policies allow public read/write with the anon key so the product works immediately.  
Before selling widely, add **Supabase Auth** and restrict policies to each business’s members.
