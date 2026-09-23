-- ============================================================================
-- Migration 023 — Verification page: seller/branch detail + full customer name
-- Phase 3 correction, approved scope:
--   1. Surface branch name / address / phone (existing `branches` table,
--      migration 008) so the public verification "SELLER" block can show
--      branch + location + contact where configured.
--   2. Return the FULL customer name for public verification, instead of the
--      masked value used since migration 022.
--
-- ----------------------------------------------------------------------------
-- WHY THE CUSTOMER NAME IS NO LONGER MASKED HERE (read before changing back)
-- ----------------------------------------------------------------------------
-- Migration 022 masked the customer name as a general P0 hardening pass.
-- Product decision (Phase 3 correction, approved): the public verification
-- result is a receipt-specific transaction record -- "who sold, who bought,
-- what, how much" -- and the customer's own name on their own receipt is the
-- product, not a leak. This function is still gated exactly as before:
--   * security definer, callable by anon/authenticated only via RPC
--   * requires the EXACT receipt_no AND a verify_id of at least 8 chars
--   * verify_id is a random per-receipt secret embedded only in that
--     receipt's QR/link -- it is not guessable or listable, so this is not a
--     customer directory or search: you must already hold the specific
--     receipt's verification link to get its customer name back.
-- The payment reference (txn) stays masked -- that was not part of this
-- approval. If a future change wants a *searchable* verification page (no
-- verify_id) or a customer list, that is a different, larger security
-- decision and must not be made by editing this function.
--
-- Everything else is unchanged: no RLS change, no new table, no relaxation
-- of who can call this function, no change to receipt immutability, tenancy
-- or branch isolation.
--
-- Safe to re-run.
-- ============================================================================

-- Output columns are being renamed (customer_masked -> customer_name), and
-- Postgres rejects CREATE OR REPLACE FUNCTION when a RETURNS TABLE column
-- name changes -- drop first so this migration actually applies cleanly.
drop function if exists public.verify_receipt(text, text);

create function public.verify_receipt(p_receipt_no text, p_verify_id text)
returns table (
  receipt_no text, status text, kind text, item text,
  amount numeric, currency text, method text,
  paid_on date, created_at timestamptz,
  customer_name text, txn_masked text,
  voided_at timestamptz,
  business_name text, business_phone text, business_email text, business_logo text,
  branch_name text, branch_address text, branch_phone text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.receipt_no, r.status, r.kind, r.item,
         r.amount, r.currency, r.method,
         r.paid_on, r.created_at,
         r.customer, public.mask_ref(r.txn),
         r.voided_at,
         b.name, b.phone, b.email, b.logo_url,
         br.name, br.address, br.phone
  from receipts r
  join businesses b on b.id = r.business_id
  left join branches br on br.id = r.branch_id
  where r.receipt_no = p_receipt_no
    and p_verify_id is not null
    and length(trim(p_verify_id)) >= 8
    and r.verify_id = p_verify_id
  limit 1;
$$;

revoke all on function public.verify_receipt(text, text) from public;
grant execute on function public.verify_receipt(text, text) to anon, authenticated;

comment on function public.verify_receipt(text, text) is
  'Public verification: requires receipt_no + a matching verify_id (min 8 chars) -- a per-receipt secret from the QR/link, not guessable or listable. Returns the FULL customer name for that specific receipt (deliberate exception approved in Phase 3 correction migration 023 -- see file header), payment reference still masked, and seller/branch identity. No internal IDs, no KYC fields (legal_name/tin/national_id are intentionally excluded).';
