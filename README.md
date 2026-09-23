# HandzJ — Theme pipeline + owner Appearance control

## Status
Public verification theme pipeline confirmed working.
Owner settings UI added so a business can pick a preset.

## Deploy

1. If not already applied: run `sql/025_theme_key.sql` in Supabase SQL Editor.
2. Deploy:
   - `public/verify.html` (public verification)
   - `public/app.html` (Business → Verification appearance)

## Owner path
Business tab → **Verification appearance**
- HandzJ System / Forest / Navy Gold / Teal Slate
- Click saves `businesses.theme_key` immediately
- Public verification links reflect the change on next load

## Scope notes
- Owner (and managers with settings access) can change appearance; RLS still allows **owner** update only on `businesses` — managers may see the same RLS limit as other profile fields.
- Does not recolor owner/manager/cashier chrome.
- Does not change receipt PNG/PDF/print layout (that remains Receipt layout presets).
- Visitor light/dark remains browser-local (`hzr_visitor_mode`).
