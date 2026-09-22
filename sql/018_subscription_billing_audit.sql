-- ============================================================================
-- HandzJ Digital Receipts — Migration 018
-- Subscription billing ledger + audit
--
-- Problem today:
--   admin_set_subscription() only flips businesses.subscription_status /
--   subscribed_until. There is no payment record, amount, MoMo reference,
--   or history of renewals/cancellations.
--
-- This migration adds:
--   • subscription_payments  — immutable commercial records
--   • admin_record_subscription_payment() — activate + log payment together
--   • admin_list_subscription_payments() / admin_subscription_billing_stats()
--   • Keeps existing admin_set_subscription for backward compatibility
--     but new admin UI should use admin_record_subscription_payment
--
-- Safe to run more than once. Run after 014–017.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Catalog of subscription products (admin can adjust prices later)
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_plan_catalog (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,          -- MONTHLY | ANNUAL
  name          text not null,
  months        int  not null check (months > 0),
  price_ugx     int  not null check (price_ugx >= 0),
  is_active     boolean not null default true,
  sort_order    int  not null default 100,
  description   text,
  created_at    timestamptz not null default now()
);

insert into public.subscription_plan_catalog (code, name, months, price_ugx, sort_order, description)
values
  ('MONTHLY', 'Business Monthly', 1,  50000,  10, 'UGX 50,000 per month — unlimited issuance while active'),
  ('ANNUAL',  'Business Annual',  12, 500000, 20, 'UGX 500,000 per year — save 2 months')
on conflict (code) do update set
  name        = excluded.name,
  months      = excluded.months,
  price_ugx   = excluded.price_ugx,
  sort_order  = excluded.sort_order,
  description = excluded.description,
  is_active   = true;

alter table public.subscription_plan_catalog enable row level security;

drop policy if exists "sub_catalog_public_read" on public.subscription_plan_catalog;
create policy "sub_catalog_public_read" on public.subscription_plan_catalog
  for select using (is_active = true);

grant select on public.subscription_plan_catalog to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Subscription payment ledger (immutable commercial history)
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_payments (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  plan_code       text not null,                 -- MONTHLY | ANNUAL | CUSTOM
  months_granted  int  not null check (months_granted > 0),
  price_ugx       int  not null default 0,
  currency        text not null default 'UGX',
  payment_ref     text,                          -- MTN/Airtel Money reference
  payment_method  text not null default 'mobile_money',
  status          text not null default 'completed'
                    check (status in ('pending','completed','refunded','cancelled','failed')),
  period_start    timestamptz not null,
  period_end      timestamptz not null,
  activated_by    uuid references auth.users(id) on delete set null,
  notes           text,
  created_at      timestamptz not null default now()
);

create index if not exists subpay_business_idx on public.subscription_payments(business_id);
create index if not exists subpay_created_idx  on public.subscription_payments(created_at desc);
create index if not exists subpay_status_idx   on public.subscription_payments(status);
create index if not exists subpay_ref_idx      on public.subscription_payments(payment_ref)
  where payment_ref is not null;

alter table public.subscription_payments enable row level security;

drop policy if exists "subpay_owner_read" on public.subscription_payments;
create policy "subpay_owner_read" on public.subscription_payments
  for select using (
    business_id = public.my_business_id()
    or public.is_platform_admin()
  );

grant select on public.subscription_payments to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Admin: list plan catalog (including inactive)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_subscription_plans()
returns setof public.subscription_plan_catalog
language sql
stable
security definer
set search_path = public
as $$
  select * from subscription_plan_catalog
  where public.is_platform_admin()
  order by sort_order, code;
$$;

grant execute on function public.admin_list_subscription_plans() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Admin: update plan price / name / active
-- ---------------------------------------------------------------------------
create or replace function public.admin_upsert_subscription_plan(
  p_code        text,
  p_name        text default null,
  p_months      int  default null,
  p_price_ugx   int  default null,
  p_is_active   boolean default null,
  p_description text default null
)
returns public.subscription_plan_catalog
language plpgsql
security definer
set search_path = public
as $$
declare
  row public.subscription_plan_catalog;
  safe_code text;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  safe_code := upper(trim(p_code));

  update subscription_plan_catalog set
    name        = coalesce(nullif(trim(coalesce(p_name, '')), ''), name),
    months      = coalesce(p_months, months),
    price_ugx   = coalesce(p_price_ugx, price_ugx),
    is_active   = coalesce(p_is_active, is_active),
    description = case when p_description is null then description
                       else nullif(trim(p_description), '') end
  where code = safe_code
  returning * into row;

  if found then
    return row;
  end if;

  if p_months is null or p_months < 1 then
    raise exception 'months required for new plan';
  end if;
  if p_price_ugx is null or p_price_ugx < 0 then
    raise exception 'price_ugx required for new plan';
  end if;

  insert into subscription_plan_catalog (code, name, months, price_ugx, is_active, description)
  values (
    safe_code,
    coalesce(nullif(trim(coalesce(p_name, '')), ''), safe_code),
    p_months,
    p_price_ugx,
    coalesce(p_is_active, true),
    nullif(trim(coalesce(p_description, '')), '')
  )
  returning * into row;

  return row;
end;
$$;

grant execute on function public.admin_upsert_subscription_plan(text, text, int, int, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Admin: record payment AND activate subscription (preferred path)
-- ---------------------------------------------------------------------------
create or replace function public.admin_record_subscription_payment(
  p_business_id   uuid,
  p_plan_code     text default 'MONTHLY',   -- MONTHLY | ANNUAL | or custom
  p_payment_ref   text default null,
  p_price_ugx     int  default null,        -- null = use catalog price
  p_months        int  default null,        -- null = use catalog months
  p_payment_method text default 'mobile_money',
  p_notes         text default null
)
returns public.subscription_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  cat     public.subscription_plan_catalog;
  months  int;
  price   int;
  plan_c  text;
  period_start timestamptz;
  period_end   timestamptz;
  payment public.subscription_payments;
  cur_until timestamptz;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;
  if p_business_id is null then
    raise exception 'Business id required';
  end if;

  plan_c := upper(trim(coalesce(p_plan_code, 'MONTHLY')));

  select * into cat from subscription_plan_catalog
   where code = plan_c and is_active = true;

  months := coalesce(p_months, cat.months, 1);
  price  := coalesce(p_price_ugx, cat.price_ugx, 0);

  if months < 1 then
    raise exception 'months must be at least 1';
  end if;

  -- Stack onto existing remaining period if still active
  select case
           when subscription_status = 'active'
            and subscribed_until is not null
            and subscribed_until > now()
           then subscribed_until
           else now()
         end
    into period_start
    from businesses where id = p_business_id;

  if period_start is null then
    raise exception 'Business not found';
  end if;

  period_end := period_start + (months || ' months')::interval;

  insert into subscription_payments (
    business_id, plan_code, months_granted, price_ugx, currency,
    payment_ref, payment_method, status,
    period_start, period_end, activated_by, notes
  ) values (
    p_business_id, plan_c, months, price, 'UGX',
    nullif(trim(coalesce(p_payment_ref, '')), ''),
    coalesce(nullif(trim(p_payment_method), ''), 'mobile_money'),
    'completed',
    period_start, period_end, auth.uid(),
    nullif(trim(coalesce(p_notes, '')), '')
  )
  returning * into payment;

  update businesses
     set subscription_status = 'active',
         plan = case when months >= 12 then 'business' else coalesce(plan, 'business') end,
         subscribed_until = period_end
   where id = p_business_id;

  -- Mirror into platform_events if present
  begin
    insert into platform_events (
      user_id, business_id, action, actor_id, result, meta
    ) values (
      auth.uid(), p_business_id, 'subscription_payment',
      auth.uid(), 'ok',
      jsonb_build_object(
        'payment_id', payment.id,
        'plan_code', plan_c,
        'months', months,
        'price_ugx', price,
        'payment_ref', payment.payment_ref,
        'period_end', period_end
      )
    );
  exception when others then
    null;
  end;

  return payment;
end;
$$;

grant execute on function public.admin_record_subscription_payment(uuid, text, text, int, int, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Patch admin_set_subscription to also write a payment row when possible
--    (backward compatible — still works if called with only months)
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_subscription(
  p_business uuid,
  p_months int default 1
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare
  out_row businesses;
  plan_c text;
  price int;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  plan_c := case when p_months >= 12 then 'ANNUAL' else 'MONTHLY' end;
  select price_ugx into price from subscription_plan_catalog where code = plan_c;
  price := coalesce(price, case when p_months >= 12 then 500000 else 50000 end);

  -- Prefer the ledger path
  perform public.admin_record_subscription_payment(
    p_business,
    plan_c,
    null,           -- no payment_ref in legacy call
    price * greatest(p_months / case when p_months >= 12 then 12 else 1 end, 1),
    greatest(p_months, 1),
    'admin',
    'Activated via admin_set_subscription (legacy)'
  );

  select * into out_row from businesses where id = p_business;
  return out_row;
end;
$$;

grant execute on function public.admin_set_subscription(uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Cancel still works; also log event
-- ---------------------------------------------------------------------------
create or replace function public.admin_cancel_subscription(p_business uuid)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare out_row businesses;
begin
  if not public.is_platform_admin() then raise exception 'Not permitted'; end if;

  update businesses
     set subscription_status = 'cancelled',
         subscribed_until = now()
   where id = p_business
  returning * into out_row;

  if not found then raise exception 'No such business'; end if;

  begin
    insert into platform_events (user_id, business_id, action, actor_id, result, meta)
    values (auth.uid(), p_business, 'subscription_cancelled', auth.uid(), 'ok',
            jsonb_build_object('cancelled_at', now()));
  exception when others then null;
  end;

  return out_row;
end;
$$;

grant execute on function public.admin_cancel_subscription(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Admin: list subscription payments
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_subscription_payments(p_limit int default 100)
returns table (
  id              uuid,
  business_id     uuid,
  business_name   text,
  plan_code       text,
  months_granted  int,
  price_ugx       int,
  payment_ref     text,
  payment_method  text,
  status          text,
  period_start    timestamptz,
  period_end      timestamptz,
  notes           text,
  created_at      timestamptz,
  subscribed_until timestamptz,
  subscription_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.business_id,
    b.name,
    p.plan_code,
    p.months_granted,
    p.price_ugx,
    p.payment_ref,
    p.payment_method,
    p.status,
    p.period_start,
    p.period_end,
    p.notes,
    p.created_at,
    b.subscribed_until,
    b.subscription_status
  from subscription_payments p
  join businesses b on b.id = p.business_id
  where public.is_platform_admin()
  order by p.created_at desc
  limit greatest(coalesce(p_limit, 100), 1);
$$;

grant execute on function public.admin_list_subscription_payments(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Admin: subscription billing stats
-- ---------------------------------------------------------------------------
create or replace function public.admin_subscription_billing_stats()
returns table (
  payments_total          bigint,
  payments_30d            bigint,
  revenue_ugx_total       bigint,
  revenue_ugx_30d         bigint,
  active_subscribers      bigint,
  expiring_7d             bigint,
  expired_not_renewed     bigint,
  monthly_plans_sold      bigint,
  annual_plans_sold       bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from subscription_payments
      where status = 'completed' and public.is_platform_admin()),
    (select count(*) from subscription_payments
      where status = 'completed' and created_at > now() - interval '30 days'
        and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from subscription_payments
      where status = 'completed' and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from subscription_payments
      where status = 'completed' and created_at > now() - interval '30 days'
        and public.is_platform_admin()),
    (select count(*) from businesses
      where subscription_status = 'active'
        and (subscribed_until is null or subscribed_until > now())
        and public.is_platform_admin()),
    (select count(*) from businesses
      where subscription_status = 'active'
        and subscribed_until is not null
        and subscribed_until > now()
        and subscribed_until <= now() + interval '7 days'
        and public.is_platform_admin()),
    (select count(*) from businesses
      where subscription_status = 'active'
        and subscribed_until is not null
        and subscribed_until <= now()
        and public.is_platform_admin()),
    (select count(*) from subscription_payments
      where status = 'completed' and plan_code = 'MONTHLY'
        and public.is_platform_admin()),
    (select count(*) from subscription_payments
      where status = 'completed' and plan_code = 'ANNUAL'
        and public.is_platform_admin());
$$;

grant execute on function public.admin_subscription_billing_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Merchant: own subscription payment history
-- ---------------------------------------------------------------------------
create or replace function public.my_subscription_payments(p_limit int default 20)
returns table (
  id              uuid,
  plan_code       text,
  months_granted  int,
  price_ugx       int,
  payment_ref     text,
  status          text,
  period_start    timestamptz,
  period_end      timestamptz,
  created_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    id, plan_code, months_granted, price_ugx, payment_ref, status,
    period_start, period_end, created_at
  from subscription_payments
  where business_id = public.my_business_id()
  order by created_at desc
  limit greatest(coalesce(p_limit, 20), 1);
$$;

grant execute on function public.my_subscription_payments(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Combined commercial revenue (packs + subscriptions) — admin
-- ---------------------------------------------------------------------------
create or replace function public.admin_commercial_revenue_summary()
returns table (
  pack_revenue_total        bigint,
  pack_revenue_30d          bigint,
  subscription_revenue_total bigint,
  subscription_revenue_30d  bigint,
  combined_revenue_total    bigint,
  combined_revenue_30d      bigint,
  active_pack_customers     bigint,
  active_subscribers        bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select coalesce(sum(price_ugx),0) from receipt_pack_purchases
      where status = 'active' and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from receipt_pack_purchases
      where status = 'active' and created_at > now() - interval '30 days'
        and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from subscription_payments
      where status = 'completed' and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from subscription_payments
      where status = 'completed' and created_at > now() - interval '30 days'
        and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from receipt_pack_purchases
      where status = 'active' and public.is_platform_admin())
    + (select coalesce(sum(price_ugx),0) from subscription_payments
        where status = 'completed' and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from receipt_pack_purchases
      where status = 'active' and created_at > now() - interval '30 days'
        and public.is_platform_admin())
    + (select coalesce(sum(price_ugx),0) from subscription_payments
        where status = 'completed' and created_at > now() - interval '30 days'
          and public.is_platform_admin()),
    (select count(distinct business_id) from receipt_pack_purchases
      where status = 'active' and pack_code not in ('FREE_5','ADMIN_GRANT')
        and public.is_platform_admin()),
    (select count(*) from businesses
      where subscription_status = 'active'
        and (subscribed_until is null or subscribed_until > now())
        and public.is_platform_admin());
$$;

grant execute on function public.admin_commercial_revenue_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- Done.
-- Preferred activation after MoMo:
--
--   select admin_record_subscription_payment(
--     '<business_uuid>',
--     'MONTHLY',           -- or 'ANNUAL'
--     'MTN-XXXXXX',        -- payment reference
--     null,                -- use catalog price
--     null,                -- use catalog months
--     'mobile_money',
--     'Paid via MTN'
--   );
--
-- Legacy admin_set_subscription(biz, months) still works and now also
-- writes a subscription_payments row.
-- ============================================================================
