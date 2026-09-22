-- ============================================================================
-- HandzJ Digital Receipts — Migration 017
-- Credit usage audit (merchant + platform admin)
--
-- Requires 014, 015, 016. Safe to run more than once.
--
-- Provides:
--   • Merchant: full personal credit ledger (my_credit_ledger)
--   • Admin: ledger for any business (admin_credit_ledger)
--   • Admin: platform-wide usage feed (admin_credit_usage_feed)
--   • Admin: per-business credit snapshot (admin_business_credit_audit)
--   • Integrity check: purchased − consumed − expired − refunded = remaining
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Merchant: own credit history (newest first)
-- ---------------------------------------------------------------------------
create or replace function public.my_credit_ledger(p_limit int default 100)
returns table (
  id              uuid,
  entry_type      text,
  credits_delta   int,
  balance_after   int,
  note            text,
  receipt_no      text,
  pack_code       text,
  payment_ref     text,
  created_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id,
    l.entry_type,
    l.credits_delta,
    l.balance_after,
    l.note,
    r.receipt_no,
    p.pack_code,
    p.payment_ref,
    l.created_at
  from receipt_credit_ledger l
  left join receipts r on r.id = l.receipt_id
  left join receipt_pack_purchases p on p.id = l.purchase_id
  where l.business_id = public.my_business_id()
  order by l.created_at desc, l.id desc
  limit greatest(coalesce(p_limit, 100), 1);
$$;

grant execute on function public.my_credit_ledger(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Admin: ledger for one business
-- ---------------------------------------------------------------------------
create or replace function public.admin_credit_ledger(
  p_business_id uuid,
  p_limit int default 200
)
returns table (
  id              uuid,
  entry_type      text,
  credits_delta   int,
  balance_after   int,
  note            text,
  receipt_id      uuid,
  receipt_no      text,
  purchase_id     uuid,
  pack_code       text,
  payment_ref     text,
  created_by      uuid,
  created_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id,
    l.entry_type,
    l.credits_delta,
    l.balance_after,
    l.note,
    l.receipt_id,
    r.receipt_no,
    l.purchase_id,
    p.pack_code,
    p.payment_ref,
    l.created_by,
    l.created_at
  from receipt_credit_ledger l
  left join receipts r on r.id = l.receipt_id
  left join receipt_pack_purchases p on p.id = l.purchase_id
  where public.is_platform_admin()
    and l.business_id = p_business_id
  order by l.created_at desc, l.id desc
  limit greatest(coalesce(p_limit, 200), 1);
$$;

grant execute on function public.admin_credit_ledger(uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Admin: platform-wide usage feed (all consumptions + purchases)
-- ---------------------------------------------------------------------------
create or replace function public.admin_credit_usage_feed(
  p_entry_type text default null,   -- null = all; 'consumption' | 'purchase' | ...
  p_limit int default 100
)
returns table (
  id              uuid,
  business_id     uuid,
  business_name   text,
  entry_type      text,
  credits_delta   int,
  balance_after   int,
  note            text,
  receipt_no      text,
  pack_code       text,
  payment_ref     text,
  created_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id,
    l.business_id,
    b.name,
    l.entry_type,
    l.credits_delta,
    l.balance_after,
    l.note,
    r.receipt_no,
    p.pack_code,
    p.payment_ref,
    l.created_at
  from receipt_credit_ledger l
  join businesses b on b.id = l.business_id
  left join receipts r on r.id = l.receipt_id
  left join receipt_pack_purchases p on p.id = l.purchase_id
  where public.is_platform_admin()
    and (p_entry_type is null or l.entry_type = p_entry_type)
  order by l.created_at desc, l.id desc
  limit greatest(coalesce(p_limit, 100), 1);
$$;

grant execute on function public.admin_credit_usage_feed(text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Admin: per-business credit audit snapshot
-- ---------------------------------------------------------------------------
create or replace function public.admin_business_credit_audit(p_limit int default 200)
returns table (
  business_id         uuid,
  business_name       text,
  owner_email         text,
  subscription_status text,
  account_status      text,
  credits_purchased   int,
  credits_consumed    int,
  credits_adjusted    int,
  credits_expired     int,
  credits_refunded    int,
  credits_remaining   int,
  balance_ok          boolean,   -- true if ledger math reconciles
  last_consumption_at timestamptz,
  last_purchase_at    timestamptz,
  receipts_issued     bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with led as (
    select
      business_id,
      coalesce(sum(credits_delta) filter (where entry_type = 'purchase'), 0)::int as purchased,
      coalesce(sum(-credits_delta) filter (where entry_type = 'consumption'), 0)::int as consumed,
      coalesce(sum(credits_delta) filter (where entry_type = 'adjustment'), 0)::int as adjusted,
      coalesce(sum(-credits_delta) filter (where entry_type = 'expiry'), 0)::int as expired,
      coalesce(sum(-credits_delta) filter (where entry_type = 'refund'), 0)::int as refunded,
      max(created_at) filter (where entry_type = 'consumption') as last_consumption_at,
      max(created_at) filter (where entry_type = 'purchase') as last_purchase_at
    from receipt_credit_ledger
    group by business_id
  )
  select
    b.id,
    b.name,
    b.email,
    coalesce(b.subscription_status, 'trialing'),
    coalesce(b.account_status, 'active'),
    coalesce(l.purchased, 0),
    coalesce(l.consumed, 0),
    coalesce(l.adjusted, 0),
    coalesce(l.expired, 0),
    coalesce(l.refunded, 0),
    public.receipt_credits_remaining(b.id),
    (
      coalesce(l.purchased, 0)
      + coalesce(l.adjusted, 0)
      - coalesce(l.consumed, 0)
      - coalesce(l.expired, 0)
      - coalesce(l.refunded, 0)
    ) = public.receipt_credits_remaining(b.id),
    l.last_consumption_at,
    l.last_purchase_at,
    (select count(*) from receipts r where r.business_id = b.id)
  from businesses b
  left join led l on l.business_id = b.id
  where public.is_platform_admin()
  order by coalesce(l.consumed, 0) desc, b.created_at desc
  limit greatest(coalesce(p_limit, 200), 1);
$$;

grant execute on function public.admin_business_credit_audit(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Admin: integrity check for one business
--    Returns a single row explaining whether the running balance matches
--    the sum of all ledger deltas.
-- ---------------------------------------------------------------------------
create or replace function public.admin_credit_integrity(p_business_id uuid)
returns table (
  business_id       uuid,
  business_name     text,
  ledger_sum        int,     -- sum of all credits_delta
  reported_balance  int,     -- latest balance_after
  remaining_fn      int,     -- receipt_credits_remaining()
  entry_count       bigint,
  is_consistent     boolean,
  detail            text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  nm text;
  s int;
  last_bal int;
  fn_bal int;
  cnt bigint;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  select name into nm from businesses where id = p_business_id;
  if nm is null then
    raise exception 'Business not found';
  end if;

  select coalesce(sum(credits_delta), 0)::int,
         count(*)
    into s, cnt
    from receipt_credit_ledger
   where business_id = p_business_id;

  select balance_after into last_bal
    from receipt_credit_ledger
   where business_id = p_business_id
   order by created_at desc, id desc
   limit 1;

  last_bal := coalesce(last_bal, 0);
  fn_bal := public.receipt_credits_remaining(p_business_id);

  business_id := p_business_id;
  business_name := nm;
  ledger_sum := s;
  reported_balance := last_bal;
  remaining_fn := fn_bal;
  entry_count := cnt;
  is_consistent := (s = last_bal and last_bal = fn_bal);
  detail := case
    when cnt = 0 then 'No ledger entries — balance correctly 0.'
    when s = last_bal and last_bal = fn_bal then 'OK — ledger sums to running balance.'
    else 'MISMATCH — investigate ledger order or missing entries.'
  end;

  return next;
end;
$$;

grant execute on function public.admin_credit_integrity(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Admin: daily consumption summary (last N days)
-- ---------------------------------------------------------------------------
create or replace function public.admin_credit_daily_usage(p_days int default 30)
returns table (
  day                 date,
  consumptions        bigint,
  credits_consumed    bigint,
  purchases           bigint,
  credits_granted     bigint,
  revenue_ugx         bigint,
  active_businesses   bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with days as (
    select generate_series(
      (current_date - (greatest(coalesce(p_days, 30), 1) - 1)),
      current_date,
      '1 day'::interval
    )::date as day
  ),
  cons as (
    select created_at::date as day,
           count(*) as consumptions,
           sum(-credits_delta) as credits_consumed,
           count(distinct business_id) as active_businesses
      from receipt_credit_ledger
     where entry_type = 'consumption'
       and created_at >= current_date - (greatest(coalesce(p_days, 30), 1) - 1)
     group by 1
  ),
  purch as (
    select created_at::date as day,
           count(*) as purchases,
           sum(credits_delta) as credits_granted
      from receipt_credit_ledger
     where entry_type = 'purchase'
       and created_at >= current_date - (greatest(coalesce(p_days, 30), 1) - 1)
     group by 1
  ),
  rev as (
    select activated_at::date as day,
           sum(price_ugx) as revenue_ugx
      from receipt_pack_purchases
     where status = 'active'
       and activated_at >= current_date - (greatest(coalesce(p_days, 30), 1) - 1)
     group by 1
  )
  select
    d.day,
    coalesce(c.consumptions, 0),
    coalesce(c.credits_consumed, 0),
    coalesce(p.purchases, 0),
    coalesce(p.credits_granted, 0),
    coalesce(r.revenue_ugx, 0),
    coalesce(c.active_businesses, 0)
  from days d
  left join cons c on c.day = d.day
  left join purch p on p.day = d.day
  left join rev r on r.day = d.day
  where public.is_platform_admin()
  order by d.day desc;
$$;

grant execute on function public.admin_credit_daily_usage(int) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Optional: log consumptions into platform_events for unified audit trail
-- ---------------------------------------------------------------------------
create or replace function public.credit_log_to_platform_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' and NEW.entry_type in ('consumption', 'purchase', 'adjustment', 'expiry', 'refund') then
    begin
      insert into platform_events (
        user_id, business_id, action, actor_id, receipt_id, result, meta
      ) values (
        NEW.created_by,
        NEW.business_id,
        'credit_' || NEW.entry_type,
        NEW.created_by,
        NEW.receipt_id,
        'ok',
        jsonb_build_object(
          'credits_delta', NEW.credits_delta,
          'balance_after', NEW.balance_after,
          'note', NEW.note,
          'ledger_id', NEW.id
        )
      );
    exception when others then
      -- Never block credit posting if platform_events is unavailable
      null;
    end;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_credit_log_platform_events on public.receipt_credit_ledger;
create trigger trg_credit_log_platform_events
  after insert on public.receipt_credit_ledger
  for each row
  execute function public.credit_log_to_platform_events();

-- ---------------------------------------------------------------------------
-- Done. Audit surfaces:
--
-- Merchant:
--   select * from my_credit_ledger(50);
--   select * from my_credit_summary();
--
-- Admin:
--   select * from admin_credit_ledger('<biz_uuid>', 100);
--   select * from admin_credit_usage_feed('consumption', 50);
--   select * from admin_business_credit_audit(100);
--   select * from admin_credit_integrity('<biz_uuid>');
--   select * from admin_credit_daily_usage(30);
-- ============================================================================
