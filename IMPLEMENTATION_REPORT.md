# HandzJ — Tenant Theme + Visitor Light/Dark

## Files in this package

| Path | Purpose |
|------|---------|
| `sql/025_theme_key.sql` | Migration: `businesses.theme_key` + extended `verify_receipt()` |
| `public/verify.html` | Public verification page with four themes × light/dark + visitor toggle |

## Apply order

1. Run `sql/025_theme_key.sql` in Supabase SQL Editor.
2. Deploy `public/verify.html` (replace existing).

## Schema change

```sql
businesses.theme_key  text NOT NULL DEFAULT 'default'
CHECK (theme_key IN ('default', 'forest', 'navy_gold', 'teal_slate'))
```

Existing businesses are backfilled to `default`.

## RPC

`verify_receipt(text, text)` returns additional column `theme_key` from the issuing business.
All prior gates (verify_id, security definer, tenant isolation) preserved.

## Visitor mode

`localStorage["hzr_visitor_mode"]` = `light` | `dark`  
Does not write to Supabase or modify tenant configuration.

## Themes

| theme_key   | Name          |
|-------------|---------------|
| default     | HandzJ System |
| forest      | Forest        |
| navy_gold   | Navy Gold     |
| teal_slate  | Teal Slate    |

Unknown values fall back to `default`. No arbitrary CSS from the database.
