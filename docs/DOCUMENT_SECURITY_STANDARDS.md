# HandzJ Digital Receipts — Document Security Standards

**Version:** 1.0  
**Status:** Binding product standard  
**Scope:** All issued digital receipts, verification records, and related audit events

This document defines the security and integrity rules that every HandzJ digital receipt must obey. It is the product-level expression of the technical controls already enforced in the database and application.

The system is a **document-record platform**, not a general SaaS dashboard. Security exists to protect the integrity of the record, not to decorate the UI.

---

## 1. Core principles

1. **A receipt is a permanent record.** Once issued, its identity and substantive content cannot be silently altered.
2. **Voiding is the only corrective action.** There is no “edit issued receipt” and no hard delete of issued documents.
3. **Verification proves retrieval, not legal authority.** The public verification page confirms that a matching record exists on the issuing platform. It does not certify tax compliance, company registration, or government status.
4. **Least privilege by design.** Tenants see only their own data. Anonymous users see nothing except through the locked verification function.
5. **Every security control must have an operational purpose** rooted in receipts, records, documents, or verification. No security theatre.

---

## 2. Document states

| State      | Meaning                                      | Transitions allowed          |
|------------|----------------------------------------------|------------------------------|
| DRAFT      | Form data only; not yet issued               | → VALID (on Issue)           |
| VALID      | Issued, permanently numbered, verifiable     | → VOIDED                     |
| VOIDED     | Explicitly cancelled by the issuer           | None (frozen)                |
| NOT FOUND  | Verification request matched no record       | N/A (query result only)      |

- **DRAFT** never receives a permanent receipt number and is never written to the cloud register.
- **VALID** and **VOIDED** are the only states that appear in the Receipt Register and on the public verification page.

---

## 3. Immutability rules

### 3.1 Issued identity fields (never change after Issue)

Once a receipt is issued, the following fields are frozen:

- `receipt_no` (permanent document identity)
- `verify_id` (secret component of the verification URL)
- `business_id`
- Customer name, item/description, amount, currency, payment method, payment reference, payment date
- Any other substantive transaction fields

### 3.2 Allowed post-issue mutation

The **only** permitted change is the transition:

```
VALID → VOIDED
```

When voiding, the system may set:

- `status = 'VOIDED'`
- `voided_at`
- `void_reason` (required)

All other columns must remain identical. The database trigger `receipts_immutability_guard` rejects any other update.

### 3.3 Voided documents

A VOIDED receipt is completely frozen. No further updates of any kind are permitted.

### 3.4 Deletion

Issued receipts (VALID or VOIDED) are never deleted. There is no client-facing or RPC delete path for issued documents. Soft-delete or hard-delete of issued records is forbidden by standard.

---

## 4. Receipt identity and numbering

- Receipt numbers are allocated atomically by the `next_receipt_no()` SECURITY DEFINER function.
- Format: `{PREFIX}-{YYYY}-{NNNNNN}` (prefix is per-business, configurable).
- Numbers are never reused, even after voiding.
- The combination of `receipt_no` + `verify_id` forms the public verification identity. Possession of the receipt number alone is insufficient to retrieve the record.

---

## 5. Public verification

### 5.1 Access path

- Public verification is performed exclusively through the `verify_receipt(receipt_no, verify_id)` RPC.
- Direct table access by the `anon` role is denied by Row Level Security.
- Both parameters are required. Enumeration of receipt numbers is not viable.

### 5.2 Returned data

The verification function returns a controlled subset of fields, with sensitive values masked where appropriate (customer name partial, payment reference partial). Full unmasked data is never exposed to anonymous callers.

### 5.3 Verification claims

The verification page must always state, in substance:

> This record was retrieved from the issuing platform.  
> This is not a government or tax authority certification.

No UI, copy, or marketing language may imply that HandzJ or the verification result constitutes official certification, tax clearance, or regulatory approval.

### 5.4 Offline / local mode

When operating without Supabase, verification links still resolve to the verification page. The page must degrade honestly (e.g. “Verification service is not configured” or equivalent) rather than invent a false positive.

---

## 6. Audit trail

### 6.1 Events recorded

Minimum required events (table `receipt_events`):

| Event type | When recorded                          | Required fields              |
|------------|----------------------------------------|------------------------------|
| ISSUED     | On successful issue                    | actor, receipt_no, timestamp |
| VOIDED     | On successful void                     | actor, reason, timestamp     |

### 6.2 Write path

- Only SECURITY DEFINER RPCs may insert into `receipt_events`.
- Clients have SELECT (own business only) and no INSERT/UPDATE/DELETE.

### 6.3 Purpose

The audit trail exists to answer: “Who issued or voided this document, and when?” It is a document-integrity log, not a full ERP event stream.

---

## 7. Access control summary

| Actor              | Receipts (own)     | Receipts (other) | Verification RPC      | Audit events (own) |
|--------------------|--------------------|------------------|-----------------------|--------------------|
| Authenticated tenant | Read / Issue / Void | None             | N/A (uses app)        | Read               |
| Anonymous visitor  | None               | None             | Yes (no + verify_id)  | None               |
| Platform owner     | Admin views only   | Admin views only | N/A                   | Admin views only   |

- Tenant isolation is enforced by `business_id = my_business_id()` derived from the signed JWT.
- The public anon key is intentionally public; it grants no direct table access.

---

## 8. Trial and subscription boundaries

- Trial expiry blocks **new issuance** only (UI + database insert policy).
- Existing records remain fully readable, printable, shareable, and voidable.
- Previously issued verification links continue to work after trial expiry.
- Subscription status must never be used as a pretext to withhold or alter historical documents.

---

## 9. Client-side obligations

The application UI must:

1. Never present an “edit issued receipt” action.
2. Require an explicit reason when voiding.
3. Display document status (VALID / VOIDED) clearly in the Register and on the document itself.
4. Preserve the verification disclaimer on the public verification page.
5. Refuse to issue when the trial has expired (and rely on the database as the final authority).

---

## 10. What this standard deliberately does not claim

- Cryptographic signing of PDF files (future option; not required by this version).
- Blockchain or external timestamping.
- Legal non-repudiation under any specific jurisdiction’s evidence rules.
- Tax authority integration or e-invoicing compliance.
- Multi-signature or dual-control workflows.

These may be added later as explicit, documented capabilities. Until then they must not appear in product language.

---

## 11. Change control

Any change that weakens immutability, broadens public verification data, removes the audit trail, or alters the document-state model requires:

1. An update to this document.
2. A corresponding database migration that preserves existing records.
3. Explicit note in the implementation / phase report.

Cosmetic UI changes that do not affect the above are outside the scope of this standard.

---

## 12. Related technical artefacts

| Artefact                              | Role                                      |
|---------------------------------------|-------------------------------------------|
| `sql/005_immutability_audit.sql`      | Trigger + `receipt_events` table          |
| `sql/002_auth_multitenant.sql`        | RLS, `my_business_id()`, trial policies   |
| `verify_receipt()` RPC                | Public verification boundary              |
| `next_receipt_no()` RPC               | Atomic numbering                          |
| `docs/AUTH_AND_TRIAL_SETUP.md`        | Auth & isolation how-to                   |
| `PHASE4_REPORT.md`                    | Product identity & design philosophy      |

---

*HandzJ Digital Receipts treats every issued receipt as a durable business record. These standards exist so that the software’s behaviour matches that claim.*
