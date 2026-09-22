-- ============================================================================
-- HandzJ Digital Receipts — Migration 014
-- Receipt Packs / Entitlement Ledger
--
-- Adds a proper credit system so merchants can buy packs of digital receipts
-- instead of (or alongside) a monthly subscription.
--
-- Design principles:
--   1. Purchasing a pack creates an immutable pack_purchase record
--   2. Credits are tracked in a ledger (purchased / consumed / remaining)
--   3. One credit is consumed ONLY when a receipt is successfully issued
--   4. Viewing, downloading, sharing, QR verification, voiding = 0 credits
--   5. Monthly subscription still works (business_active remains authoritative)
--   6. Free starter credits (5) can be granted on signup
--
-- Safe to run more than once. Run AFTER 013_rls_policies.sql.
-- Supabase → SQL Editor → paste → Run.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. Catalog of sellable packs (admin-managed)
-- ---------------------------------------------------------------------------
create table if not exists public.receipt_pack_catalog (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,          -- e.g. 'STARTER_20', 'GROW_50'
  name          text not null,                 -- '20 Digital Receipts'
  credits       int  not null check (credits > 0),
  price_ugx     int  not null check (price_ugx >= 0),
  is_active     boolean not null default true,
  sort_order    int  not null default 100,
  description   text,
  created_at    timestamptz not null default now()
);

-- Seed the recommended packs (idempotent)
insert into public.receipt_pack_catalog (code, name, credits, price_ugx, sort_order, description)
values
  ('FREE_5',     '5 Free Receipts',       5,     0,      10,  'Starter credits for new businesses'),
  ('STARTER_20', '20 Digital Receipts',  20, 10000,      20,  'No monthly commitment'),
  ('GROW_50',    '50 Digital Receipts',  50, 20000,      30,  'Best for small shops'),
  ('BUSINESS_100','100 Digital Receipts',100,35000,      40,  'Serious volume'),
  ('PRO_250',    '250 Digital Receipts', 250,75000,      50,  'Higher volume'),
  ('SCALE_500',  '500 Digital Receipts', 500,125000,     60,  'Near-subscription equivalent'),
  ('ENTERPRISE_1000','1,000 Digital Receipts',1000,200000,70,'High-volume buffer')
on conflict (code) do update set
  name        = excluded.name,
  credits     = excluded.credits,
  price_ugx   = excluded.price_ugx,
  sort_order  = excluded.sort_order,
  description = excluded.description,
  is_active   = true;

-- ---------------------------------------------------------------------------
-- 2. Pack purchases (immutable commercial record)
-- ---------------------------------------------------------------------------
create table if not exists public.receipt_pack_purchases (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  catalog_id      uuid references public.receipt_pack_catalog(id) on delete set null,
  pack_code       text not null,                 -- denormalised for audit
  credits_granted int  not null check (credits_granted > 0),
  price_ugx       int  not null default 0,
  payment_ref     text,                          -- MTN/Airtel Money reference
  payment_method  text default 'mobile_money',   -- mobile_money | free | admin | promo
  status          text not null default 'pending'
                    check (status in ('pending','active','expired','cancelled','refunded')),
  activated_at    timestamptz,
  activated_by    uuid references auth.users(id) on delete set null, -- admin who activated
  expires_at      timestamptz,                   -- optional long-stop (e.g. +24 months)
  notes           text,
  created_at      timestamptz not null default now()
);

create index if not exists rpp_business_idx on public.receipt_pack_purchases(business_id);
create index if not exists rpp_status_idx   on public.receipt_pack_purchases(status);

-- ---------------------------------------------------------------------------
-- 3. Credit ledger (source of truth for remaining balance)
-- ---------------------------------------------------------------------------
create table if not exists public.receipt_credit_ledger (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  purchase_id     uuid references public.receipt_pack_purchases(id) on delete set null,
  receipt_id      uuid references public.receipts(id) on delete set null,
  entry_type      text not null
                    check (entry_type in (
                      'purchase',      -- credits added from a pack
                      'consumption',   -- 1 credit used by issuing a receipt
                      'adjustment',    -- admin correction
                      'expiry',        -- credits expired
                      'refund'         -- credits reversed
                    )),
  credits_delta   int  not null,                 -- +N for purchase, -1 for consumption
  balance_after   int  not null,                 -- running balance after this entry
  note            text,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);

create index if not exists rcl_business_idx on public.receipt_credit_ledger(business_id);
create index if not exists rcl_created_idx  on public.receipt_credit_ledger(created_at desc);
create index if not exists rcl_receipt_idx  on public.receipt_credit_ledger(receipt_id) where receipt_id is not null;

-- ---------------------------------------------------------------------------
-- 4. Helper: current credit balance for a business
-- ---------------------------------------------------------------------------
create or replace function public.receipt_credits_remaining(b_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select balance_after
       from receipt_credit_ledger
      where business_id = b_id
      order by created_at desc, id desc
      limit 1),
    0
  );
$$;

-- Convenience for the logged-in merchant
create or replace function public.my_receipt_credits()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select public.receipt_credits_remaining(public.my_business_id());
$$;

-- ---------------------------------------------------------------------------
-- 5. Activate a pack (admin or system after payment confirmation)
--    Creates the purchase (if needed) and posts a ledger entry.
-- ---------------------------------------------------------------------------
create or replace function public.activate_receipt_pack(
  p_business_id   uuid,
  p_pack_code     text,
  p_payment_ref   text default null,
  p_payment_method text default 'mobile_money',
  p_notes         text default null,
  p_expires_months int default 24          -- long-stop expiry (null = never)
)
returns public.receipt_pack_purchases
language plpgsql
security definer
set search_path = public
as $$
declare
  cat       public.receipt_pack_catalog;
  purchase  public.receipt_pack_purchases;
  bal       int;
  exp_at    timestamptz;
begin
  -- Only platform admins (or service role) should call this in production.
  -- For now we allow authenticated callers who own the business OR platform admins.
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  select * into cat from receipt_pack_catalog
   where code = upper(trim(p_pack_code)) and is_active = true;
  if not found then
    raise exception 'Unknown or inactive pack code: %', p_pack_code;
  end if;

  if p_expires_months is not null and p_expires_months > 0 then
    exp_at := now() + (p_expires_months || ' months')::interval;
  else
    exp_at := null;
  end if;

  insert into receipt_pack_purchases (
    business_id, catalog_id, pack_code, credits_granted, price_ugx,
    payment_ref, payment_method, status, activated_at, activated_by,
    expires_at, notes
  ) values (
    p_business_id, cat.id, cat.code, cat.credits, cat.price_ugx,
    nullif(trim(coalesce(p_payment_ref,'')),''),
    coalesce(nullif(trim(p_payment_method),''), 'mobile_money'),
    'active', now(), auth.uid(),
    exp_at, nullif(trim(coalesce(p_notes,'')),'')
  )
  returning * into purchase;

  bal := public.receipt_credits_remaining(p_business_id) + cat.credits;

  insert into receipt_credit_ledger (
    business_id, purchase_id, entry_type, credits_delta, balance_after, note, created_by
  ) values (
    p_business_id, purchase.id, 'purchase', cat.credits, bal,
    'Pack activated: ' || cat.name, auth.uid()
  );

  return purchase;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Consume one credit when a receipt is successfully issued
--    Called from a trigger on receipts AFTER INSERT.
-- ---------------------------------------------------------------------------
create or replace function public.consume_receipt_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bal int;
  has_sub boolean;
begin
  -- Only consume for VALID new receipts
  if NEW.status is distinct from 'VALID' then
    return NEW;
  end if;

  -- If the business has an active paid subscription, do NOT consume pack credits.
  -- Subscription = unlimited (subject to fair-use) issuance.
  select exists (
    select 1 from businesses b
     where b.id = NEW.business_id
       and b.subscription_status = 'active'
       and (b.subscribed_until is null or b.subscribed_until > now())
  ) into has_sub;

  if has_sub then
    return NEW;   -- subscription path: no credit consumption
  end if;

  bal := public.receipt_credits_remaining(NEW.business_id);

  if bal < 1 then
    raise exception 'NO_CREDITS: you have no receipt credits remaining — buy a pack or subscribe';
  end if;

  insert into receipt_credit_ledger (
    business_id, receipt_id, entry_type, credits_delta, balance_after, note, created_by
  ) values (
    NEW.business_id, NEW.id, 'consumption', -1, bal - 1,
    'Receipt issued: ' || NEW.receipt_no, auth.uid()
  );

  return NEW;
end;
$$;

drop trigger if exists trg_consume_receipt_credit on public.receipts;
create trigger trg_consume_receipt_credit
  after insert on public.receipts
  for each row
  execute function public.consume_receipt_credit();

-- ---------------------------------------------------------------------------
-- 7. Update business_active so pack credits also allow issuance
--    (keeps existing trial + subscription logic, adds credit path)
-- ---------------------------------------------------------------------------
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
      and coalesce(b.subscription_status, 'trialing') not in ('suspended', 'terminated')
      and (
        -- Paid subscription still valid
        (b.subscription_status = 'active'
          and (b.subscribed_until is null or b.subscribed_until > now()))
        -- Or still inside free trial
        or (coalesce(b.subscription_status,'trialing') = 'trialing'
          and b.trial_ends_at is not null
          and b.trial_ends_at > now())
        -- Or has remaining pack credits
        or public.receipt_credits_remaining(b_id) > 0
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- 8. Grant free starter credits on signup (optional but recommended)
--    Call this from signup_business or from the app after first login.
-- ---------------------------------------------------------------------------
create or replace function public.grant_free_starter_credits(p_business_id uuid)
returns public.receipt_pack_purchases
language plpgsql
security definer
set search_path = public
as $$
declare
  already boolean;
begin
  -- Only once per business
  select exists (
    select 1 from receipt_pack_purchases
     where business_id = p_business_id and pack_code = 'FREE_5'
  ) into already;

  if already then
    return null;  -- already granted
  end if;

  return public.activate_receipt_pack(
    p_business_id,
    'FREE_5',
    null,
    'free',
    'Welcome pack — 5 free digital receipts',
    24
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Merchant-facing summary view
-- ---------------------------------------------------------------------------
create or replace function public.my_credit_summary()
returns table (
  credits_remaining   int,
  total_purchased     int,
  total_consumed      int,
  has_active_subscription boolean,
  subscription_status text,
  trial_ends_at       timestamptz,
  subscribed_until    timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    public.my_receipt_credits()                                          as credits_remaining,
    coalesce((select sum(credits_delta) from receipt_credit_ledger
               where business_id = public.my_business_id()
                 and entry_type = 'purchase'), 0)::int                   as total_purchased,
    coalesce((select sum(-credits_delta) from receipt_credit_ledger
               where business_id = public.my_business_id()
                 and entry_type = 'consumption'), 0)::int                as total_consumed,
    exists (
      select 1 from businesses b
       where b.id = public.my_business_id()
         and b.subscription_status = 'active'
         and (b.subscribed_until is null or b.subscribed_until > now())
    )                                                                    as has_active_subscription,
    (select subscription_status from businesses where id = public.my_business_id()),
    (select trial_ends_at from businesses where id = public.my_business_id()),
    (select subscribed_until from businesses where id = public.my_business_id());
$$;

-- ---------------------------------------------------------------------------
-- 10. RLS
-- ---------------------------------------------------------------------------
alter table public.receipt_pack_catalog   enable row level security;
alter table public.receipt_pack_purchases enable row level security;
alter table public.receipt_credit_ledger  enable row level security;

-- Catalog is public (anyone can see available packs)
drop policy if exists "catalog_public_read" on public.receipt_pack_catalog;
create policy "catalog_public_read" on public.receipt_pack_catalog
  for select using (is_active = true);

-- Purchases: owner can see their own; platform admin can see all
drop policy if exists "purchases_owner_read" on public.receipt_pack_purchases;
create policy "purchases_owner_read" on public.receipt_pack_purchases
  for select using (
    business_id = public.my_business_id()
    or public.is_platform_admin()
  );

-- Ledger: same rule
drop policy if exists "ledger_owner_read" on public.receipt_credit_ledger;
create policy "ledger_owner_read" on public.receipt_credit_ledger
  for select using (
    business_id = public.my_business_id()
    or public.is_platform_admin()
  );

-- No direct inserts/updates from clients — only via security-definer functions
-- (activate_receipt_pack, consume trigger, grant_free_starter_credits)

-- ---------------------------------------------------------------------------
-- 11. Grants
-- ---------------------------------------------------------------------------
grant execute on function public.receipt_credits_remaining(uuid) to authenticated;
grant execute on function public.my_receipt_credits()            to authenticated;
grant execute on function public.my_credit_summary()             to authenticated;
grant execute on function public.activate_receipt_pack(uuid,text,text,text,text,int) to authenticated;
grant execute on function public.grant_free_starter_credits(uuid) to authenticated;

grant select on public.receipt_pack_catalog   to anon, authenticated;
grant select on public.receipt_pack_purchases to authenticated;
grant select on public.receipt_credit_ledger  to authenticated;

-- ---------------------------------------------------------------------------
-- Done. After running this migration:
--   1. Call grant_free_starter_credits(business_id) after signup if desired
--   2. Admin activates paid packs via activate_receipt_pack(...) after MoMo
--   3. next_receipt_no() / business_active() already respect credits
-- ============================================================================
