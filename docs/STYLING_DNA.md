# HandzJ Styling DNA — reference

Discovered from what already exists in Digital Receipts (verify.html's document
card, index.html's structural chrome), not invented from scratch, and not a
full design-system document — just the rules worth reusing across HandzJ
products.

## The core idea

HandzJ product surfaces read like **records and ledgers**, not app cards.
Status reads like a **signal** (a mark + a word), not a coloured pill.
Structure comes from **borders**, not shadows. Emphasis comes from
**typographic register** (serif/tracked/mono), not decoration.

## 1. Shape language — sharp for records, soft only for controls

Two radius scales, used deliberately, not interchangeably:

- **Record/structural surfaces** (document cards, panels, tables, the app
  shell, list rows): `0–3px`. These represent the business's actual data —
  they should look printed/issued, not floated.
- **Interactive controls** (buttons, inputs, toasts, floating actions):
  `6–8px`. A human taps these; a slight softness signals "this responds to
  you" without breaking the document feel around it.

Never give a receipt, a table, or a status document 12–16px "app card"
rounding. That's the generic-SaaS tell this DNA exists to avoid.

## 2. Borders over shadows

Default to a `1px solid var(--line)` border. Add one **accent border**
(top or bottom, 2–3px, brand colour) to mark identity or a section head —
this is already how `verify.html`'s document header works. Reserve
`box-shadow` for things that are genuinely floating above content (a toast,
a WhatsApp float button, a modal) — never for a card sitting in normal flow.

## 3. Status is a signal, not a pill

Canonical pattern, already live in `verify.html`: a **ring mark** (circle,
2–3px border, symbol inside) paired with a **tracked-uppercase word label**.
Colour carries meaning (green = confirmed, red = voided, amber = attention,
grey = unknown) but the *shape* — ring + word — is what makes it recognisably
HandzJ, not just "a green badge." Use this same pattern for receipt status,
subscription status, staff status, branch status — anywhere in any HandzJ
product a record has a state.

Small inline table/list statuses may compress to a dot + label, but keep the
ring+word treatment for anywhere status is the primary thing being reported.

## 4. Typography carries the hierarchy

- **IBM Plex Serif, uppercase, tracked** — identity and section heads
  (business name, page mastheads, status labels, section titles). This is
  the "official document" register.
- **IBM Plex Sans** — everything operational: body text, forms, nav,
  descriptions.
- **Tabular/monospace numerals** — every amount, receipt number, reference,
  verification ID, date. Numbers that represent *data* get a different
  rhythm than prose around them, the way they would on a printed receipt.
  This is already partly present (`.mono`, `font-variant-numeric:tabular-nums`)
  and should become a standard utility, not an occasional touch.

Labels above data use a small (11–12px), letter-spaced, uppercase eyebrow —
already the `.k` / eyebrow pattern in the demo receipt and verify page.

## 5. Colour has a job, not a mood

- **Deep Ink / Graphite** — system and control surfaces: navigation, table
  headers, the app shell chrome. Where the *system* is speaking.
- **Warm Ivory** — the working surface. Breathing room around records.
- **Signal Green** — confirmed / active / valid. Earned, not decorative.
- **Deep Green** — depth and authority: hover/pressed states, primary
  emphasis on dark chrome.
- **Amber** — attention needed: trial ending, pending action, a warning that
  isn't yet an error.
- **Muted red** (supplemental, not in the core palette) — voided/error only.

Colour should never be the only differentiator across a full page (the
brief's own warning against "green/amber-heavy composition" applies). Most
of a screen stays ink-on-ivory or ink-on-white; colour marks the handful of
things that matter right now.

## 6. Product personality within the shared DNA

Same family, different emphasis, per the brief:
- **Digital Receipts** — records → verification → communication. The
  document/ledger register above is at its strongest here.
- Future products (HZ POS, HZ SENTE, Bingo Vintage, etc.) inherit the same
  shape/border/status/type rules but can weight colour and layout toward
  their own operational centre (movement, collections, field operations).
  Not defined further here — out of scope for this task.

## What this replaces from the phase-1 stylesheet

`assets/handzj.css` initially shipped generic defaults (14px card radius,
drop-shadow cards, pill-shaped status badges) that fought the product's own
existing language rather than extending it. Corrected in the same file:
record surfaces now use sharp radii and border-only structure; the canonical
status component is a ring+label, matching `verify.html`; a `.hz-num`
utility standardises tabular numerals for amounts/references site-wide.
