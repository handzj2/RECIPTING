# Marketing image compression settings

Applied to all responsive variants under this folder.

## JPEG (fallback)

| Width | Quality | Notes |
|-------|---------|--------|
| 640   | 78      | Mobile / narrow |
| 960   | 80      | Default `src` |
| 1168  | 82      | Full / retina-ish |

- Progressive (`progressive=True`)
- `optimize=True`
- Chroma subsampling **4:2:0**
- Metadata stripped (PIL re-encode)
- Resample: **Lanczos**

## WebP (preferred via `<source type="image/webp">`)

| Width | Quality | Notes |
|-------|---------|--------|
| 640   | 72      | Aggressive for mobile |
| 960   | 75      | Default mid |
| 1168  | 78      | Largest |

- `method=6` (slower encode, smaller files)
- Metadata stripped

## HTML usage

- Prefer WebP in `<picture><source type="image/webp" …>`
- JPEG in `<img srcset>` fallback
- `sizes`: hero `(max-width:720px) 100vw, 720px` · gallery `(max-width:720px) 100vw, 50vw`
- Below-fold: `loading="lazy"` · Hero: `fetchpriority="high"`

## Re-run (from this directory)

```bash
python3 - <<'PY'
from PIL import Image
from pathlib import Path
# see project scripts or re-apply settings in COMPRESSION.md
PY
```

Or ImageMagick equivalent:

```bash
convert SRC.jpg -strip -interlace Plane -sampling-factor 4:2:0 -quality 80 -resize 960x\> OUT-960.jpg
convert SRC.jpg -strip -quality 75 -define webp:method=6 -resize 960x\> OUT-960.webp
```

## Do not

- Serve full unoptimized originals on the homepage (keep as masters only)
- Use quality &lt; 70 on hero (visible banding)
- Skip `width`/`height` or `aspect-ratio` (CLS)
