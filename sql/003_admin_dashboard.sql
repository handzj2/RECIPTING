-- ============================================================================
-- HandzJ Digital Receipts — Migration 003
-- Owner dashboard: see every business that signs up, their trial/subscription
-- state, how much they're actually using the tool, and switch them on when they pay.
--
-- Run AFTER 002_auth_multitenant.sql. Safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Who is allowed to see the owner dashboard
-- ---------------------------------------------------------------------------
create table if not exists platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz default now()
);

alter table platform_admins enable row level security;
-- No client policies at all: the table is only ever read from SECURITY DEFINER
-- functions below. A tenant cannot read it, and cannot add themselves to it.

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from platform_admins where user_id = auth.uid());
$$;

grant execute on function public.is_platform_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The subscriber list
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_businesses()
returns table (
  id uuid,
  name text,
  owner_email text,
  phone text,
  whatsapp text,
  prefix text,
  signed_up_at timestamptz,
  subscription_status text,
  trial_ends_at timestamptz,
  subscribed_until timestamptz,
  days_left int,
  state text,
  receipts_count bigint,
  receipts_valid bigint,
  last_receipt_at timestamptz,
  total_billed numeric,
  currency text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id,
    b.name,
    coalesce(u.email, b.email)                                as owner_email,
    b.phone,
    b.whatsapp,
    b.prefix,
    b.created_at                                              as signed_up_at,
    coalesce(b.subscription_status, 'trialing')               as subscription_status,
    b.trial_ends_at,
    b.subscribed_until,
    case
      when b.subscription_status = 'active' and b.subscribed_until is not null
        then greatest(0, ceil(extract(epoch from (b.subscribed_until - now())) / 86400))::int
      when coalesce(b.subscription_status,'trialing') = 'trialing' and b.trial_ends_at is not null
        then greatest(0, ceil(extract(epoch from (b.trial_ends_at - now())) / 86400))::int
      else null
    end                                                       as days_left,
    case
      when b.subscription_status = 'active'
       and (b.subscribed_until is null or b.subscribed_until > now())        then 'SUBSCRIBED'
      when b.subscription_status = 'active'                                  then 'SUB_EXPIRED'
      when coalesce(b.subscription_status,'trialing') = 'trialing'
       and b.trial_ends_at > now()                                           then 'TRIAL'
      when coalesce(b.subscription_status,'trialing') = 'trialing'           then 'TRIAL_ENDED'
      else upper(coalesce(b.subscription_status, 'UNKNOWN'))
    end                                                       as state,
    count(r.id)                                               as receipts_count,
    count(r.id) filter (where r.status = 'VALID')             as receipts_valid,
    max(r.created_at)                                         as last_receipt_at,
    coalesce(sum(r.amount) filter (where r.status = 'VALID'), 0) as total_billed,
    max(r.currency)                                           as currency
  from businesses b
  left join auth.users u on u.id = b.owner_id
  left join receipts r  on r.business_id = b.id
  where public.is_platform_admin()          -- non-admins get zero rows, always
  group by b.id, u.email
  order by b.created_at desc;
$$;

grant execute on function public.admin_list_businesses() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Headline numbers for the dashboard cards
-- ---------------------------------------------------------------------------
create or replace function public.admin_stats()
returns table (
  businesses_total bigint,
  subscribed bigint,
  on_trial bigint,
  trial_ended bigint,
  signups_7d bigint,
  signups_30d bigint,
  trials_ending_3d bigint,
  receipts_total bigint,
  receipts_30d bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(*),
    count(*) filter (where b.subscription_status = 'active'
                       and (b.subscribed_until is null or b.subscribed_until > now())),
    count(*) filter (where coalesce(b.subscription_status,'trialing') = 'trialing'
                       and b.trial_ends_at > now()),
    count(*) filter (where coalesce(b.subscription_status,'trialing') = 'trialing'
                       and (b.trial_ends_at is null or b.trial_ends_at <= now())),
    count(*) filter (where b.created_at > now() - interval '7 days'),
    count(*) filter (where b.created_at > now() - interval '30 days'),
    count(*) filter (where coalesce(b.subscription_status,'trialing') = 'trialing'
                       and b.trial_ends_at between now() and now() + interval '3 days'),
    (select count(*) from receipts),
    (select count(*) from receipts where created_at > now() - interval '30 days')
  from businesses b
  where public.is_platform_admin();
$$;

grant execute on function public.admin_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Actions: switch a client on when they pay, or give more trial
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_subscription(
  p_business uuid,
  p_months int default 1          -- use 12 for a year, 0 for open-ended
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare out_row businesses;
begin
  if not public.is_platform_admin() then raise exception 'Not permitted'; end if;

  update businesses
     set subscription_status = 'active',
         plan = case when p_months >= 12 then 'business' else 'starter' end,
         subscribed_until = case
            when p_months <= 0 then null
            else greatest(coalesce(subscribed_until, now()), now()) + (p_months || ' months')::interval
         end
   where id = p_business
   returning * into out_row;

  if not found then raise exception 'No such business'; end if;
  return out_row;
end;
$$;

create or replace function public.admin_extend_trial(
  p_business uuid,
  p_days int default 5
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare out_row businesses;
begin
  if not public.is_platform_admin() then raise exception 'Not permitted'; end if;

  update businesses
     set subscription_status = 'trialing',
         trial_ends_at = greatest(coalesce(trial_ends_at, now()), now()) + (p_days || ' days')::interval
   where id = p_business
   returning * into out_row;

  if not found then raise exception 'No such business'; end if;
  return out_row;
end;
$$;

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
  return out_row;
end;
$$;

grant execute on function public.admin_set_subscription(uuid, int) to authenticated;
grant execute on function public.admin_extend_trial(uuid, int) to authenticated;
grant execute on function public.admin_cancel_subscription(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. MAKE YOURSELF THE ADMIN  ← you must run this, replacing the email
-- ---------------------------------------------------------------------------
insert into platform_admins (user_id, email)
select id, email from auth.users where email = 'handzj2@gmail.com'
on conflict (user_id) do nothing;

-- Check it worked (should return your row):
-- select * from platform_admins;
