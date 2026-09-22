-- ============================================================================
-- HandzJ Digital Receipts — Migration 015
-- Platform-admin control of receipt-pack pricing + monitoring
--
-- Requires 014_receipt_packs_ledger.sql to have been run first.
-- Safe to run more than once.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Revised starter catalog (includes UGX 5,000 entry pack)
--    Admin can change any of these live from the dashboard later.
-- ---------------------------------------------------------------------------
insert into public.receipt_pack_catalog (code, name, credits, price_ugx, sort_order, description, is_active)
values
  ('FREE_5',          '5 Free Receipts',         5,      0,  10, 'Welcome credits for new businesses', true),
  ('ENTRY_10',        '10 Digital Receipts',    10,   5000,  15, 'Lowest-cost entry pack', true),
  ('STARTER_20',      '20 Digital Receipts',    20,  10000,  20, 'No monthly commitment', true),
  ('GROW_50',         '50 Digital Receipts',    50,  20000,  30, 'Best for small shops', true),
  ('BUSINESS_100',    '100 Digital Receipts',  100,  35000,  40, 'Serious volume', true),
  ('PRO_250',         '250 Digital Receipts',  250,  75000,  50, 'Higher volume', true),
  ('SCALE_500',       '500 Digital Receipts',  500, 125000,  60, 'Near-subscription equivalent', true),
  ('ENTERPRISE_1000', '1,000 Digital Receipts',1000, 200000,  70, 'High-volume buffer', true)
on conflict (code) do update set
  name        = excluded.name,
  credits     = excluded.credits,
  price_ugx   = excluded.price_ugx,
  sort_order  = excluded.sort_order,
  description = excluded.description,
  is_active   = excluded.is_active;

-- ---------------------------------------------------------------------------
-- 2. Admin: list full catalog (including inactive)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_pack_catalog()
returns setof public.receipt_pack_catalog
language sql
stable
security definer
set search_path = public
as $$
  select * from receipt_pack_catalog
  where public.is_platform_admin()
  order by sort_order, code;
$$;

grant execute on function public.admin_list_pack_catalog() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Admin: create or update a pack in the catalog
--    Pass p_id = null to create; pass p_id to update.
-- ---------------------------------------------------------------------------
create or replace function public.admin_upsert_pack(
  p_id          uuid default null,
  p_code        text default null,
  p_name        text default null,
  p_credits     int  default null,
  p_price_ugx   int  default null,
  p_is_active   boolean default null,
  p_sort_order  int  default null,
  p_description text default null
)
returns public.receipt_pack_catalog
language plpgsql
security definer
set search_path = public
as $$
declare
  row public.receipt_pack_catalog;
  safe_code text;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  if p_id is not null then
    -- UPDATE existing
    update receipt_pack_catalog set
      code        = coalesce(nullif(upper(trim(p_code)), ''), code),
      name        = coalesce(nullif(trim(p_name), ''), name),
      credits     = coalesce(p_credits, credits),
      price_ugx   = coalesce(p_price_ugx, price_ugx),
      is_active   = coalesce(p_is_active, is_active),
      sort_order  = coalesce(p_sort_order, sort_order),
      description = case when p_description is null then description else nullif(trim(p_description), '') end
    where id = p_id
    returning * into row;

    if not found then
      raise exception 'Pack not found';
    end if;
    return row;
  end if;

  -- CREATE new
  if p_code is null or length(trim(p_code)) < 2 then
    raise exception 'Pack code is required';
  end if;
  if p_name is null or length(trim(p_name)) < 2 then
    raise exception 'Pack name is required';
  end if;
  if p_credits is null or p_credits < 1 then
    raise exception 'Credits must be at least 1';
  end if;
  if p_price_ugx is null or p_price_ugx < 0 then
    raise exception 'Price must be 0 or greater';
  end if;

  safe_code := upper(regexp_replace(trim(p_code), '[^A-Za-z0-9_]', '', 'g'));

  insert into receipt_pack_catalog (code, name, credits, price_ugx, is_active, sort_order, description)
  values (
    safe_code,
    trim(p_name),
    p_credits,
    p_price_ugx,
    coalesce(p_is_active, true),
    coalesce(p_sort_order, 100),
    nullif(trim(coalesce(p_description, '')), '')
  )
  returning * into row;

  return row;
end;
$$;

grant execute on function public.admin_upsert_pack(uuid, text, text, int, int, boolean, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Admin: soft-disable a pack (does not delete history)
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_pack_active(p_id uuid, p_active boolean)
returns public.receipt_pack_catalog
language plpgsql
security definer
set search_path = public
as $$
declare
  row public.receipt_pack_catalog;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  update receipt_pack_catalog
     set is_active = coalesce(p_active, false)
   where id = p_id
  returning * into row;

  if not found then
    raise exception 'Pack not found';
  end if;
  return row;
end;
$$;

grant execute on function public.admin_set_pack_active(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Admin: activate a pack for a specific business (after Mobile Money)
--    Wrapper that enforces platform-admin check more explicitly for the UI.
-- ---------------------------------------------------------------------------
create or replace function public.admin_activate_pack_for_business(
  p_business_id   uuid,
  p_pack_code     text,
  p_payment_ref   text default null,
  p_notes         text default null,
  p_expires_months int default 24
)
returns public.receipt_pack_purchases
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;
  if p_business_id is null then
    raise exception 'Business id required';
  end if;
  return public.activate_receipt_pack(
    p_business_id,
    p_pack_code,
    p_payment_ref,
    'mobile_money',
    p_notes,
    p_expires_months
  );
end;
$$;

grant execute on function public.admin_activate_pack_for_business(uuid, text, text, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Admin: grant free / promo credits without payment
-- ---------------------------------------------------------------------------
create or replace function public.admin_grant_credits(
  p_business_id uuid,
  p_credits     int,
  p_note        text default 'Admin grant'
)
returns public.receipt_pack_purchases
language plpgsql
security definer
set search_path = public
as $$
declare
  purchase public.receipt_pack_purchases;
  bal int;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;
  if p_credits is null or p_credits < 1 then
    raise exception 'Credits must be at least 1';
  end if;

  insert into receipt_pack_purchases (
    business_id, pack_code, credits_granted, price_ugx,
    payment_method, status, activated_at, activated_by, notes
  ) values (
    p_business_id, 'ADMIN_GRANT', p_credits, 0,
    'admin', 'active', now(), auth.uid(), nullif(trim(coalesce(p_note,'')), '')
  )
  returning * into purchase;

  bal := public.receipt_credits_remaining(p_business_id) + p_credits;

  insert into receipt_credit_ledger (
    business_id, purchase_id, entry_type, credits_delta, balance_after, note, created_by
  ) values (
    p_business_id, purchase.id, 'purchase', p_credits, bal,
    coalesce(nullif(trim(p_note), ''), 'Admin grant'), auth.uid()
  );

  return purchase;
end;
$$;

grant execute on function public.admin_grant_credits(uuid, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Admin monitoring: pack sales summary
-- ---------------------------------------------------------------------------
create or replace function public.admin_pack_stats()
returns table (
  packs_sold_total        bigint,
  packs_sold_30d          bigint,
  credits_granted_total   bigint,
  credits_consumed_total  bigint,
  credits_remaining_total bigint,
  revenue_ugx_total       bigint,
  revenue_ugx_30d         bigint,
  active_pack_customers   bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from receipt_pack_purchases
      where status = 'active' and pack_code <> 'FREE_5' and pack_code <> 'ADMIN_GRANT'
        and public.is_platform_admin()),
    (select count(*) from receipt_pack_purchases
      where status = 'active' and pack_code <> 'FREE_5' and pack_code <> 'ADMIN_GRANT'
        and created_at > now() - interval '30 days'
        and public.is_platform_admin()),
    (select coalesce(sum(credits_delta),0) from receipt_credit_ledger
      where entry_type = 'purchase' and public.is_platform_admin()),
    (select coalesce(sum(-credits_delta),0) from receipt_credit_ledger
      where entry_type = 'consumption' and public.is_platform_admin()),
    (select coalesce(sum(public.receipt_credits_remaining(b.id)),0)
       from businesses b where public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from receipt_pack_purchases
      where status = 'active' and public.is_platform_admin()),
    (select coalesce(sum(price_ugx),0) from receipt_pack_purchases
      where status = 'active' and created_at > now() - interval '30 days'
        and public.is_platform_admin()),
    (select count(distinct business_id) from receipt_pack_purchases
      where status = 'active' and pack_code not in ('FREE_5','ADMIN_GRANT')
        and public.is_platform_admin());
$$;

grant execute on function public.admin_pack_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Admin: list recent pack purchases (for the monitor table)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_pack_purchases(p_limit int default 100)
returns table (
  id              uuid,
  business_id     uuid,
  business_name   text,
  pack_code       text,
  credits_granted int,
  price_ugx       int,
  payment_ref     text,
  payment_method  text,
  status          text,
  activated_at    timestamptz,
  expires_at      timestamptz,
  notes           text,
  created_at      timestamptz,
  credits_remaining int
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
    p.pack_code,
    p.credits_granted,
    p.price_ugx,
    p.payment_ref,
    p.payment_method,
    p.status,
    p.activated_at,
    p.expires_at,
    p.notes,
    p.created_at,
    public.receipt_credits_remaining(p.business_id)
  from receipt_pack_purchases p
  join businesses b on b.id = p.business_id
  where public.is_platform_admin()
  order by p.created_at desc
  limit greatest(coalesce(p_limit, 100), 1);
$$;

grant execute on function public.admin_list_pack_purchases(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Admin: credit balance for one business (used when activating)
-- ---------------------------------------------------------------------------
create or replace function public.admin_business_credits(p_business_id uuid)
returns table (
  credits_remaining int,
  total_purchased   int,
  total_consumed    int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    public.receipt_credits_remaining(p_business_id),
    coalesce((select sum(credits_delta)::int from receipt_credit_ledger
               where business_id = p_business_id and entry_type = 'purchase'), 0),
    coalesce((select sum(-credits_delta)::int from receipt_credit_ledger
               where business_id = p_business_id and entry_type = 'consumption'), 0)
  where public.is_platform_admin();
$$;

grant execute on function public.admin_business_credits(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Done. Platform admin can now:
--   • List / create / edit / disable packs (admin_list_pack_catalog, admin_upsert_pack, admin_set_pack_active)
--   • Activate a paid pack for a business after MoMo (admin_activate_pack_for_business)
--   • Grant free/promo credits (admin_grant_credits)
--   • Monitor sales & consumption (admin_pack_stats, admin_list_pack_purchases)
-- ============================================================================
