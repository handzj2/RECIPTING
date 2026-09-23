# HandzJ Marketing Images — Full Responsive + Modern Formats (Sep 2026)

## Complete set (ready to drop into `public/assets/marketing/`)

| Base name                  | Role / Best placement                                | Orientation |
|----------------------------|------------------------------------------------------|-------------|
| `market-vendor-valid`      | Lifestyle, Features, How-it-works, Homepage gallery  | Landscape  |
| `hardware-phone-print`     | Dual digital + paper proof, Trust, Features          | Landscape  |
| `beauty-lounge-valid`      | Service business examples, Features, Verification    | Portrait   |
| `phone-repair-valid`       | Hero, Public verification, Trust section             | Portrait   |

### Files per image
- `NAME.jpg`               → master
- `NAME-640.jpg` / `.webp` / `.avif`
- `NAME-960.jpg` / `.webp` / `.avif`
- `NAME-1168.jpg` / `.webp` / `.avif`

## Modern `<picture>` (recommended – includes AVIF)

```html
<picture>
  <!-- AVIF first (best compression) -->
  <source type="image/avif"
    srcset="/assets/marketing/NAME-640.avif 640w,
            /assets/marketing/NAME-960.avif 960w,
            /assets/marketing/NAME-1168.avif 1168w"
    sizes="(max-width:720px) 100vw, 50vw">

  <!-- WebP fallback -->
  <source type="image/webp"
    srcset="/assets/marketing/NAME-640.webp 640w,
            /assets/marketing/NAME-960.webp 960w,
            /assets/marketing/NAME-1168.webp 1168w"
    sizes="(max-width:720px) 100vw, 50vw">

  <!-- JPEG final fallback -->
  <img
    src="/assets/marketing/NAME-960.jpg"
    srcset="/assets/marketing/NAME-640.jpg 640w,
            /assets/marketing/NAME-960.jpg 960w,
            /assets/marketing/NAME-1168.jpg 1168w"
    sizes="(max-width:720px) 100vw, 50vw"
    width="1168" height="784"
    alt="HandzJ Digital Receipts – [description]"
    loading="lazy"
    decoding="async">
</picture>
```

### Notes
- Portrait images → use `width="784" height="1168"`
- True hero / LCP image → add `fetchpriority="high"` and remove `loading="lazy"`
- Gallery / below-fold → keep `loading="lazy"`

### Suggested `sizes` values
- Full-width hero: `sizes="100vw"`
- Two-column gallery: `sizes="(max-width:720px) 100vw, 50vw"`
- Small cards / sidebar: `sizes="(max-width:720px) 100vw, 300px"`

### Alt text suggestions
- market-vendor-valid: "Market vendor in Uganda verifying a digital receipt on HandzJ – VALID RECEIPT for Nakasero Fresh Market"
- hardware-phone-print: "HandzJ digital receipt on phone next to matching printed thermal receipt at Kira Hardware & Tools"
- beauty-lounge-valid: "Valid digital receipt for HandzJ Beauty Lounge hair treatment shown on phone"
- phone-repair-valid: "Public verification of a valid HandzJ digital receipt for phone repair"

Ready for production.
