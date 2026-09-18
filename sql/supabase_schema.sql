-- HandzJ Digital Receipts — Supabase schema (multi-business ready)
-- Run in Supabase → SQL Editor (once)

create extension if not exists "pgcrypto";

create table if not exists businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tagline text,
  phone text,
  whatsapp text,
  email text,
  logo_url text,
  plan text default 'starter',
  created_at timestamptz default now()
);

create table if not exists receipts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id) on delete cascade,
  receipt_no text not null,
  verify_id text not null,
  status text not null default 'VALID',
  kind text not null default 'software',
  customer text not null,
  cust_email text,
  cust_phone text,
  item text not null,
  pkg text,
  period text,
  proj_ref text,
  description text,
  amount numeric not null,
  currency text not null default 'UGX',
  method text,
  txn text,
  paid_on date,
  received_by text,
  notes text,
  created_at timestamptz default now(),
  voided_at timestamptz,
  void_reason text,
  unique (business_id, receipt_no)
);

create index if not exists receipts_business_idx on receipts(business_id);
create index if not exists receipts_no_idx on receipts(receipt_no);
create index if not exists receipts_verify_idx on receipts(verify_id);
create index if not exists receipts_created_idx on receipts(created_at desc);

create table if not exists receipt_sequences (
  business_id uuid references businesses(id) on delete cascade,
  year int not null,
  seq int not null default 0,
  primary key (business_id, year)
);

-- Seed default business (optional — app can also create this)
insert into businesses (name, tagline, phone, whatsapp, email, plan)
select
  'HANDZJ TECH SOLUTIONS',
  'We Build Brands. We Power Systems. We Drive Growth.',
  '0781 909 507',
  '0757 632 884',
  'handzj2@gmail.com',
  'business'
where not exists (
  select 1 from businesses where name = 'HANDZJ TECH SOLUTIONS'
);

alter table receipts enable row level security;
alter table businesses enable row level security;
alter table receipt_sequences enable row level security;

-- Starter policies: open read/write with anon key (tighten when you add Auth)
drop policy if exists "biz_select" on businesses;
drop policy if exists "biz_insert" on businesses;
drop policy if exists "biz_update" on businesses;
create policy "biz_select" on businesses for select using (true);
create policy "biz_insert" on businesses for insert with check (true);
create policy "biz_update" on businesses for update using (true);

drop policy if exists "rcp_select" on receipts;
drop policy if exists "rcp_insert" on receipts;
drop policy if exists "rcp_update" on receipts;
create policy "rcp_select" on receipts for select using (true);
create policy "rcp_insert" on receipts for insert with check (true);
create policy "rcp_update" on receipts for update using (true);

drop policy if exists "seq_all" on receipt_sequences;
create policy "seq_all" on receipt_sequences for all using (true) with check (true);
