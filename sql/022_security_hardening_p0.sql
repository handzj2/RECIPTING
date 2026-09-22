-- 022_security_hardening_p0.sql
-- P0/P1 security follow-ups. Safe patterns; preserves verify_receipt return shape.

-- 1) Optional abuse signal table (service role / future definer writers only)
create table if not exists public.verify_attempt_log (
  id bigserial primary key,
  receipt_no text,
  ip_hash text,
  ok boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists verify_attempt_log_created_idx
  on public.verify_attempt_log (created_at desc);

alter table public.verify_attempt_log enable row level security;
-- No anon/authenticated policies → not readable/writable from the client.

-- 2) Harden verify_receipt: reject null/short verify_id; keep masked columns
create or replace function public.verify_receipt(p_receipt_no text, p_verify_id text)
returns table (
  receipt_no text, status text, kind text, item text,
  amount numeric, currency text, method text,
  paid_on date, created_at timestamptz,
  customer_masked text, txn_masked text,
  voided_at timestamptz,
  business_name text, business_phone text, business_email text, business_logo text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.receipt_no, r.status, r.kind, r.item,
         r.amount, r.currency, r.method,
         r.paid_on, r.created_at,
         public.mask_name(r.customer), public.mask_ref(r.txn),
         r.voided_at,
         b.name, b.phone, b.email, b.logo_url
  from receipts r
  join businesses b on b.id = r.business_id
  where r.receipt_no = p_receipt_no
    and p_verify_id is not null
    and length(trim(p_verify_id)) >= 8
    and r.verify_id = p_verify_id
  limit 1;
$$;

revoke all on function public.verify_receipt(text, text) from public;
grant execute on function public.verify_receipt(text, text) to anon, authenticated;

comment on function public.verify_receipt(text, text) is
  'Public verification: requires receipt_no + verify_id (min 8 chars). Returns masked fields only.';
