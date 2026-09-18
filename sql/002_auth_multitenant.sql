-- ============================================================================
-- HandzJ Digital Receipts — Migration 002
-- Turns the single-business tool into a real multi-tenant SaaS:
--   1. Every business is owned by a Supabase Auth user (email + password)
--   2. Row Level Security so Business A can never read/write Business B
--   3. A 5-day free trial per signup, enforced in the DATABASE (not just the UI)
--   4. Public receipt verification via a locked-down RPC (no open table reads)
--
-- Safe to run more than once. Run AFTER supabase_schema.sql.
-- Supabase → SQL Editor → paste → Run.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. Tenant columns on businesses
-- ---------------------------------------------------------------------------
alter table businesses add column if not exists owner_id uuid references auth.users(id) on delete cascade;
alter table businesses add column if not exists prefix text;
alter table businesses add column if not exists trial_ends_at timestamptz;
alter table businesses add column if not exists subscription_status text default 'trialing';
alter table businesses add column if not exists subscribed_until timestamptz;

-- One business per login account. Keeps ownership unambiguous.
create unique index if not exists businesses_owner_uidx on businesses(owner_id) where owner_id is not null;

-- Receipt prefix must be unique-ish per tenant so numbers don't collide visually
update businesses set prefix = 'HJT' where prefix is null and name = 'HANDZJ TECH SOLUTIONS';
update businesses set prefix = upper(left(regexp_replace(coalesce(name,'BIZ'), '[^A-Za-z]', '', 'g'), 3))
  where prefix is null or prefix = '';

alter table businesses alter column subscription_status set default 'trialing';

-- ---------------------------------------------------------------------------
-- 2. Helper functions
-- ---------------------------------------------------------------------------

-- The business owned by the currently logged-in user (null if none).
create or replace function public.my_business_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from businesses where owner_id = auth.uid() limit 1;
$$;

-- Is a tenant allowed to WRITE right now? (inside trial, or paid up)
create or replace function public.business_active(b_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from businesses b
    where b.id = b_id
      and (
        b.subscription_status = 'active' and (b.subscribed_until is null or b.subscribed_until > now())
        or (coalesce(b.subscription_status,'trialing') = 'trialing' and b.trial_ends_at is not null and b.trial_ends_at > now())
      )
  );
$$;

-- Partially hide a customer name for the public verification page.
create or replace function public.mask_name(src text)
returns text
language plpgsql
immutable
as $$
declare
  parts text[];
  out_t text;
  i int;
begin
  if src is null or length(trim(src)) = 0 then return '—'; end if;
  parts := regexp_split_to_array(trim(src), '\s+');
  out_t := parts[1];
  for i in 2 .. coalesce(array_length(parts,1),1) loop
    out_t := out_t || ' ' || upper(left(parts[i],1)) || '•';
  end loop;
  return out_t;
end;
$$;

create or replace function public.mask_ref(src text)
returns text
language sql
immutable
as $$
  select case
    when src is null or length(src) = 0 then '—'
    when length(src) <= 4 then repeat('•', length(src))
    else left(src, 2) || repeat('•', greatest(length(src) - 4, 1)) || right(src, 2)
  end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Signup: create the tenant for the logged-in user, start the 5-day trial
--    Called by login.html straight after sign-up succeeds.
-- ---------------------------------------------------------------------------
create or replace function public.signup_business(
  p_name text,
  p_tagline text default null,
  p_phone text default null,
  p_whatsapp text default null,
  p_email text default null,
  p_prefix text default null
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare
  existing businesses;
  created businesses;
  safe_prefix text;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  select * into existing from businesses where owner_id = auth.uid() limit 1;
  if found then
    return existing;  -- idempotent: re-running signup never creates a second tenant
  end if;

  if p_name is null or length(trim(p_name)) < 2 then
    raise exception 'Business name is required';
  end if;

  safe_prefix := upper(regexp_replace(coalesce(nullif(trim(p_prefix),''), p_name), '[^A-Za-z]', '', 'g'));
  safe_prefix := left(coalesce(nullif(safe_prefix,''), 'BIZ'), 4);

  insert into businesses (owner_id, name, tagline, phone, whatsapp, email, prefix,
                          plan, subscription_status, trial_ends_at)
  values (auth.uid(), trim(p_name), nullif(trim(coalesce(p_tagline,'')),''),
          nullif(trim(coalesce(p_phone,'')),''), nullif(trim(coalesce(p_whatsapp,'')),''),
          coalesce(nullif(trim(coalesce(p_email,'')),''), auth.email()),
          safe_prefix, 'trial', 'trialing',
          now() + interval '5 days')          -- <<< 5-DAY FREE TRIAL
  returning * into created;

  return created;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Atomic receipt numbering for the caller's own business
-- ---------------------------------------------------------------------------
create or replace function public.next_receipt_no()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid;
  b_prefix text;
  yr int := extract(year from now())::int;
  n int;
  candidate text;
  guard int := 0;
begin
  b_id := public.my_business_id();
  if b_id is null then raise exception 'No business for this account'; end if;
  if not public.business_active(b_id) then
    raise exception 'TRIAL_EXPIRED: your free trial has ended — subscribe to keep issuing receipts';
  end if;

  select coalesce(prefix,'BIZ') into b_prefix from businesses where id = b_id;

  insert into receipt_sequences (business_id, year, seq)
  values (b_id, yr, 1)
  on conflict (business_id, year) do update set seq = receipt_sequences.seq + 1
  returning seq into n;

  loop
    candidate := b_prefix || '-' || yr || '-' || lpad(n::text, 6, '0');
    exit when not exists (
      select 1 from receipts where business_id = b_id and receipt_no = candidate
    );
    guard := guard + 1;
    if guard > 200 then raise exception 'Could not allocate a receipt number'; end if;
    update receipt_sequences set seq = seq + 1
      where business_id = b_id and year = yr returning seq into n;
  end loop;

  return candidate;
end;
$$;

-- Peek at the next number without consuming one (for the UI readout)
create or replace function public.peek_receipt_no()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(b.prefix,'BIZ') || '-' || extract(year from now())::int || '-' ||
         lpad((coalesce(s.seq,0) + 1)::text, 6, '0')
  from businesses b
  left join receipt_sequences s
    on s.business_id = b.id and s.year = extract(year from now())::int
  where b.id = public.my_business_id();
$$;

-- ---------------------------------------------------------------------------
-- 5. Public verification RPC — the ONLY thing an anonymous visitor can call.
--    Returns masked fields only. Requires BOTH the receipt number and the
--    verification id, so numbers can't be enumerated.
-- ---------------------------------------------------------------------------
drop function if exists public.verify_receipt(text, text);
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
    and r.verify_id = p_verify_id
  limit 1;
$$;

grant execute on function public.verify_receipt(text, text) to anon, authenticated;
grant execute on function public.signup_business(text,text,text,text,text,text) to authenticated;
grant execute on function public.next_receipt_no() to authenticated;
grant execute on function public.peek_receipt_no() to authenticated;
grant execute on function public.my_business_id() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. LOCK DOWN THE TABLES
--    Everything below replaces the old "using (true)" free-for-all policies.
-- ---------------------------------------------------------------------------
alter table businesses          enable row level security;
alter table receipts            enable row level security;
alter table receipt_sequences   enable row level security;

-- --- businesses ---
drop policy if exists "biz_select" on businesses;
drop policy if exists "biz_insert" on businesses;
drop policy if exists "biz_update" on businesses;
drop policy if exists "biz_owner_select" on businesses;
drop policy if exists "biz_owner_insert" on businesses;
drop policy if exists "biz_owner_update" on businesses;

create policy "biz_owner_select" on businesses
  for select to authenticated
  using (owner_id = auth.uid());

create policy "biz_owner_insert" on businesses
  for insert to authenticated
  with check (owner_id = auth.uid());

create policy "biz_owner_update" on businesses
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
-- note: no delete policy, and no policy at all for `anon` → anonymous visitors
-- get zero rows from this table.

-- --- receipts ---
drop policy if exists "rcp_select" on receipts;
drop policy if exists "rcp_insert" on receipts;
drop policy if exists "rcp_update" on receipts;
drop policy if exists "rcp_owner_select" on receipts;
drop policy if exists "rcp_owner_insert" on receipts;
drop policy if exists "rcp_owner_update" on receipts;

create policy "rcp_owner_select" on receipts
  for select to authenticated
  using (business_id = public.my_business_id());

-- Writes require an ACTIVE tenant: trial still running, or subscribed.
create policy "rcp_owner_insert" on receipts
  for insert to authenticated
  with check (
    business_id = public.my_business_id()
    and public.business_active(business_id)
  );

-- Updates (voiding) stay allowed after expiry so records remain correctable,
-- but only ever on your own receipts.
create policy "rcp_owner_update" on receipts
  for update to authenticated
  using (business_id = public.my_business_id())
  with check (business_id = public.my_business_id());

-- --- receipt_sequences ---
drop policy if exists "seq_all" on receipt_sequences;
drop policy if exists "seq_owner" on receipt_sequences;
create policy "seq_owner" on receipt_sequences
  for select to authenticated
  using (business_id = public.my_business_id());
-- writes happen only inside next_receipt_no() (security definer), so no
-- insert/update policy is granted to clients at all.

-- ---------------------------------------------------------------------------
-- 7. Claim the existing HANDZJ business (run ONCE, after you sign up)
--    Uncomment, replace the email, run it. This attaches all existing receipts
--    to your new login instead of leaving them ownerless.
-- ---------------------------------------------------------------------------
-- update businesses
--    set owner_id = (select id from auth.users where email = 'handzj2@gmail.com'),
--        subscription_status = 'active',
--        subscribed_until = null,
--        prefix = 'HJT'
--  where name = 'HANDZJ TECH SOLUTIONS';

-- Sanity check: any business with no owner is now invisible to the app.
-- select id, name, owner_id, prefix, subscription_status, trial_ends_at from businesses;
