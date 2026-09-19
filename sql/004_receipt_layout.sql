-- Per-client receipt layout (theme presets + JSON override)
-- Safe to re-run.
alter table businesses
  add column if not exists receipt_layout jsonb default null;

comment on column businesses.receipt_layout is
  'Optional JSON: {theme, align, blocks, show, labels, extras, custom_css}. null = classic defaults.';

-- Expose theme on the admin list so the platform owner can see who customized.
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
  currency text,
  receipt_layout jsonb
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
    max(r.currency)                                           as currency,
    b.receipt_layout
  from businesses b
  left join auth.users u on u.id = b.owner_id
  left join receipts r  on r.business_id = b.id
  where public.is_platform_admin()
  group by b.id, u.email
  order by b.created_at desc;
$$;

grant execute on function public.admin_list_businesses() to authenticated;
