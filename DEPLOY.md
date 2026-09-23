# HandzJ deploy package

## Folder map

```
HandzJ_Deploy/
├── DEPLOY.md                 ← this file
├── sql/
│   ├── 025_theme_key.sql           # businesses.theme_key + verify_receipt
│   ├── 026_set_business_theme.sql  # owner/manager set theme RPC
│   └── 025_VERIFY_AFTER.sql        # optional post-migrate checks
└── public/
    ├── index.html                  # homepage + responsive marketing images
    ├── verify.html                 # public verification (4 themes × light/dark)
    ├── app.html                    # owner app (Verification appearance)
    └── assets/marketing/           # brand images (JPEG + WebP 640/960/1168)
```

## 1. Database (Supabase SQL Editor)

Run in order:

1. `sql/025_theme_key.sql`   — skip if already applied  
2. `sql/026_set_business_theme.sql`  
3. Optional: `sql/025_VERIFY_AFTER.sql`

## 2. Static files (Vercel / host)

Merge into your site root so paths match production:

| Package path | Deploy to |
|--------------|-----------|
| `public/index.html` | `/index.html` (or project `public/index.html`) |
| `public/verify.html` | `/verify.html` |
| `public/app.html` | `/app.html` |
| `public/assets/marketing/*` | `/assets/marketing/*` |

Do **not** overwrite unrelated files (config.js, logo, other pages) unless you intend to.

## 3. Smoke check after deploy

- [ ] Home loads; hero + “See it in use” images appear  
- [ ] Network tab: WebP on supporting browsers; smaller width on mobile  
- [ ] `/verify?no=…&id=…` still verifies  
- [ ] Business → Verification appearance saves a theme  
- [ ] Verify page respects theme + visitor light/dark toggle  

## Theme keys

`default` | `forest` | `navy_gold` | `teal_slate`
