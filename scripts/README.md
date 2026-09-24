# HandzJ Image Validation Scripts

Automated checks for marketing images used across the Digital Receipts application.

## Scripts

| Script | Requirements | Purpose |
|--------|--------------|---------|
| `validate-images.py` | Python 3 + (optional) Pillow | Full validation: references, complete sets, dimensions, naming, orphans |
| `validate-images.sh` | bash + (optional) ImageMagick `identify` | Fast CI-friendly check |

## Quick start

```bash
# From project root
./scripts/validate-images.sh

# Strict mode (warnings become failures)
./scripts/validate-images.sh --strict

# Full Python report
python3 scripts/validate-images.py

# Machine-readable
python3 scripts/validate-images.py --json
```

## What is checked

1. **HTML references** – every `/assets/marketing/...` path in `public/*.html` must exist and be non-empty
2. **Complete size sets** – for each known image family the 640 / 960 / 1168 variants must exist in jpg + webp + avif
3. **Orientation** – landscape sets must be wider than tall; portrait sets the opposite
4. **Naming** – kebab-case + optional size suffix
5. **Orphans** – files present but never referenced (info only)

## Known image sets

```
hands-verify-valid          (landscape)  – original
receipt-phone-and-print     (landscape)  – original
desk-owner-and-verify       (landscape)  – original
hero-verify-phone           (landscape)  – original
market-vendor-valid         (landscape)  – new
hardware-phone-print        (landscape)  – new
beauty-lounge-valid         (portrait)   – new
phone-repair-valid          (portrait)   – new
```

## CI integration example

```yaml
# GitHub Actions / similar
- name: Validate marketing images
  run: ./scripts/validate-images.sh --strict
```

Exit codes:
- `0` – pass
- `1` – validation failed
- `2` – setup error (missing directory etc.)
