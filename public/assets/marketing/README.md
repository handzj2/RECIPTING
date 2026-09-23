# HandzJ marketing images — responsive set

## Files per shot

| Base name | Role |
|-----------|------|
| `hands-verify-valid` | Customer VALID |
| `receipt-phone-and-print` | Phone + paper receipt |
| `desk-owner-and-verify` | Owner + customer desk |
| `hero-verify-phone` | Hero / brand |

Each has: original `.jpg`, plus `-640` / `-960` / `-1168` in **JPEG** and **WebP**.

## Responsive pattern (already on index.html)

```html
<picture>
  <source type="image/webp"
    srcset="/assets/marketing/NAME-640.webp 640w,
            /assets/marketing/NAME-960.webp 960w,
            /assets/marketing/NAME-1168.webp 1168w"
    sizes="(max-width:720px) 100vw, 50vw">
  <img
    src="/assets/marketing/NAME-960.jpg"
    srcset="/assets/marketing/NAME-640.jpg 640w,
            /assets/marketing/NAME-960.jpg 960w,
            /assets/marketing/NAME-1168.jpg 1168w"
    sizes="(max-width:720px) 100vw, 50vw"
    width="1168" height="784"
    alt="…"
    loading="lazy"
    decoding="async">
</picture>
```

- Hero image: `fetchpriority="high"`, no `loading="lazy"`
- Below-fold gallery: `loading="lazy"`
- `width`/`height` + CSS `aspect-ratio` reduce layout shift
