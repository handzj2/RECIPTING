-- ============================================================================
-- Migration 025 — Tenant theme_key for public verification surface
-- Approved four-theme design gate.
--
-- Scope (do not expand):
--   1. Add businesses.theme_key (text, NOT NULL, default 'default')
--      Allowed: default | forest | navy_gold | teal_slate
--   2. Extend verify_receipt() to return theme_key from the issuing business
--
-- Constraints:
--   * No themes table
--   * No per-business arbitrary CSS/color storage
--   * Existing businesses remain valid (default)
--   * Preserve tenant isolation, verify_id gate, security definer,
--     masking rules, receipt immutability, RLS
--   * Theme is for public verification only — not internal apps
--
-- Safe to re-run.
-- ============================================================================

-- 1) Tenant-scoped theme key
alter table public.businesses
  add column if not exists theme_key text;

-- Backfill existing rows before NOT NULL
update public.businesses
  set theme_key = 'default'
  where theme_key is null;

alter table public.businesses
  alter column theme_key set default 'default';

alter table public.businesses
  alter column theme_key set not null;

-- Drop prior check if re-running, then enforce allowed values
alter table public.businesses
  drop constraint if exists businesses_theme_key_check;

alter table public.businesses
  add constraint businesses_theme_key_check
  check (theme_key in ('default', 'forest', 'navy_gold', 'teal_slate'));

comment on column public.businesses.theme_key is
  'Public verification visual identity. Allowed: default, forest, navy_gold, teal_slate. Not used by owner/manager/cashier/admin apps.';

-- 2) Extend verify_receipt to return theme_key from issuing business
-- Column list grows (theme_key added) — drop first so CREATE applies cleanly.
drop function if exists public.verify_receipt(text, text);

create function public.verify_receipt(p_receipt_no text, p_verify_id text)
returns table (
  receipt_no text, status text, kind text, item text,
  amount numeric, currency text, method text,
  paid_on date, created_at timestamptz,
  customer_name text, txn_masked text,
  voided_at timestamptz,
  business_name text, business_phone text, business_email text, business_logo text,
  branch_name text, branch_address text, branch_phone text,
  theme_key text
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
         br.name, br.address, br.phone,
         coalesce(nullif(trim(b.theme_key), ''), 'default')
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
  'Public verification: requires receipt_no + matching verify_id (min 8 chars). Returns full customer name, masked payment ref, seller/branch identity, and businesses.theme_key for controlled public theme resolution. No internal IDs, no KYC fields.';
