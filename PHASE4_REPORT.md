# Phase 4 — HandzJ Product Identity & Structural Refinement

## Goal

Move the product away from generic AI/SaaS dashboard aesthetics toward a credible **document-record system**:

> Issue → Register → Document → Verify → Record

Every UI decision and code organisation choice should reinforce that model.

## What changed

### 1. Navigation (app chrome)
- Tabs renamed and reordered to domain language:
  - **Issue Receipt** (primary action)
  - **Receipt Register** (operational centre)
  - **Business** (identity & settings)
- Top bar: solid brand colour, bottom accent rule, no gradient, reduced radius.
- Product title: `HANDZJ DIGITAL RECEIPTS` · `Record · Issue · Verify`

### 2. Issue Receipt — document desk
- Two-column layout: form (left) + live receipt preview (right).
- Form grouped into clear sections: **Customer**, **Transaction**.
- Primary action is **Issue Receipt**; Preview is secondary.
- Preview panel sticky on large screens.

### 3. Receipt Register — operational centre
- Table-first view (Date · Receipt · Customer · Amount · Status).
- Search + status + date filters retained.
- No summary metric cards. The register *is* the work surface.

### 4. Verification page (`verify.html`)
- Completely redesigned as a document identity:
  - Header with receipt number
  - Large status mark (✓ / ✕ / ?) and label (VALID / VOIDED / NOT FOUND)
  - Structured key/value block
  - Issuer bar
  - Explicit disclaimer (not government/tax certification)
- No generic cards, no glass, no decorative gradients.

### 5. Marketing site (`index.html`)
- Lead with the actual product:
  - Sample receipt + live-looking verification card side by side.
- Headline: “Digital receipts that can be verified.”
- Workflow steps: Issue → Deliver → Verify.
- Removed generic “ultimate solution” language and heavy gradient hero tropes.

### 6. Visual system (anti-generic)
Banned / reduced:
- Gradient hero / gradient topbar
- Large border-radius (cards → 2px)
- Heavy multi-layer shadows
- Glass / floating panels
- Metric summary cards as the home screen
- “Welcome back” / emoji / AI-powered labels

Retained / strengthened:
- Barlow Condensed for document titles and receipt numbers
- Strong type hierarchy and letter-spacing
- Controlled spacing
- Navy brand with cyan accent rule
- Document states: VALID · VOIDED · DRAFT · NOT FOUND

### 7. Code structure (conceptual)
No rewrite into frameworks. Existing monolithic pages kept for stability.
Conceptual modules (for future progressive extraction):

```
receipts/     issue · register · document · verification
business/     identity · branding
auth/         login · signup · password-reset
admin/        businesses · subscription
shared/       formatting · validation · security · UI primitives
```

## Preserved
- Receipt engine (issue, void, QR, PDF, WhatsApp, email)
- Multi-tenant Supabase model and trial gate
- Backward-compatible verification URLs (hash → clean verify.html)
- Admin owner dashboard

## Design rule (permanent)
No feature, screen, component or visual pattern should be introduced merely because it is common in SaaS applications. Every element must have a documented operational purpose rooted in receipts, records, documents, verification and business transactions.

## Next recommended steps
1. Live-update the issue preview as fields change (currently requires Preview click).
2. Extract shared document renderer into a single pure function used by issue preview, view, and PDF.
3. Progressive module files under `public/js/` if the monolith grows further.
4. Align login.html and admin.html chrome with the same document-system visual language.

---

## Related standard added after Phase 4

**`docs/DOCUMENT_SECURITY_STANDARDS.md`** codifies the document-level security model:

- Document states and allowed transitions (DRAFT → VALID → VOIDED)
- Immutability of issued identity and transaction fields
- Void-only correction path
- Public verification boundary and required disclaimer
- Minimal audit trail (ISSUED / VOIDED)
- Explicit non-claims (no tax/government certification)

This standard is the durable product expression of the controls already present in
`sql/005_immutability_audit.sql` and the multi-tenant RLS policies.
