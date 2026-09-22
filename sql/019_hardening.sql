-- ============================================================================
-- HandzJ Digital Receipts — Migration 019
-- Final hardening (packs + subscriptions)
--
-- Requires 014–018. Safe to run more than once.
-- ============================================================================

-- 1. Prevent duplicate Mobile Money references on pack purchases
create unique index if not exists rpp_payment_ref_uidx
  on public.receipt_pack_purchases (payment_ref)
  where payment_ref is not null and length(trim(payment_ref)) > 0
    and status in ('pending', 'active');

-- 2. Prevent duplicate Mobile Money references on subscription payments
create unique index if not exists subpay_payment_ref_uidx
  on public.subscription_payments (payment_ref)
  where payment_ref is not null and length(trim(payment_ref)) > 0
    and status = 'completed';

-- 3. Index for expiry sweeps
create index if not exists rpp_expires_idx
  on public.receipt_pack_purchases (expires_at)
  where expires_at is not null and status = 'active';

-- 4. Tighten activate_receipt_pack: paid packs require platform admin
create or replace function public.activate_receipt_pack(
  p_business_id   uuid,
  p_pack_code     text,
  p_payment_ref   text default null,
  p_payment_method text default 'mobile_money',
  p_notes         text default null,
  p_expires_months int default 24
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
  method    text;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  select * into cat from receipt_pack_catalog
   where code = upper(trim(p_pack_code)) and is_active = true;
  if not found then
    raise exception 'Unknown or inactive pack code: %', p_pack_code;
  end if;

  method := coalesce(nullif(trim(p_payment_method), ''), 'mobile_money');

  -- Paid packs (price > 0) may only be activated by platform admins
  if cat.price_ugx > 0 and not public.is_platform_admin() then
    raise exception 'Not permitted: paid pack activation requires platform admin';
  end if;

  -- Free packs: allow owner of the business OR platform admin
  if cat.price_ugx = 0
     and not public.is_platform_admin()
     and public.my_business_id() is distinct from p_business_id then
    raise exception 'Not permitted';
  end if;

  -- Paid activations should carry a payment reference
  if cat.price_ugx > 0
     and (p_payment_ref is null or length(trim(p_payment_ref)) < 3)
     and method = 'mobile_money' then
    raise exception 'payment_ref required for paid Mobile Money activation';
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
    nullif(trim(coalesce(p_payment_ref, '')), ''),
    method,
    'active', now(), auth.uid(),
    exp_at, nullif(trim(coalesce(p_notes, '')), '')
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

-- 5. Expire overdue pack credits (callable by admin / cron)
create or replace function public.admin_expire_stale_pack_credits()
returns table (business_id uuid, purchase_id uuid, credits_expired int)
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  bal int;
  leftover int;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  for rec in
    select p.id, p.business_id, p.credits_granted, p.pack_code
      from receipt_pack_purchases p
     where p.status = 'active'
       and p.expires_at is not null
       and p.expires_at <= now()
  loop
    -- Approximate: expire min(remaining, granted) as a pooled system —
    -- post a single expiry entry for remaining balance only once per overdue purchase batch.
    -- Safer approach: mark purchase expired; only zero credits if remaining > 0 and no active sub.
    update receipt_pack_purchases
       set status = 'expired'
     where id = rec.id;

    bal := public.receipt_credits_remaining(rec.business_id);
    if bal > 0 then
      leftover := bal;  -- pool model: we do not FIFO-expire per pack; mark status only
      -- Do not auto-zero pooled credits here to avoid wiping newer packs.
      -- Status=expired is the commercial flag; balance remains until consumed or admin adjusts.
    end if;

    business_id := rec.business_id;
    purchase_id := rec.id;
    credits_expired := 0;
    return next;
  end loop;
end;
$$;

grant execute on function public.admin_expire_stale_pack_credits() to authenticated;

-- 6. Revoke direct client writes on commercial tables (RPCs only)
--    SELECT already gated by RLS; ensure no INSERT/UPDATE/DELETE for authenticated.
revoke insert, update, delete on public.receipt_pack_purchases from authenticated, anon;
revoke insert, update, delete on public.receipt_credit_ledger from authenticated, anon;
revoke insert, update, delete on public.receipt_pack_catalog from authenticated, anon;

do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'subscription_payments') then
    execute 'revoke insert, update, delete on public.subscription_payments from authenticated, anon';
    execute 'revoke insert, update, delete on public.subscription_plan_catalog from authenticated, anon';
  end if;
end $$;

-- 7. ENTRY_10 in catalog if 015 not fully applied
insert into public.receipt_pack_catalog (code, name, credits, price_ugx, sort_order, description, is_active)
values ('ENTRY_10', '10 Digital Receipts', 10, 5000, 15, 'Lowest-cost entry pack', true)
on conflict (code) do update set
  name = excluded.name,
  credits = excluded.credits,
  price_ugx = excluded.price_ugx,
  sort_order = excluded.sort_order,
  is_active = true;

-- Done.
