-- ============================================================================
-- HandzJ Digital Receipts — COMBINED MIGRATION 010 → 013
-- Run this ENTIRE script once in Supabase → SQL Editor → Run
-- Do NOT paste the filename — paste this file's CONTENTS.
--
-- Includes:
--   010  KYC, audit log, suspend, phone login resolver
--   011  Lock business name + receipt prefix (admin can edit)
--   012  Logo lock + one-time admin grant
--   013  Row Level Security policies
-- ============================================================================


-- ############################################################################
-- BEGIN 010_kyc_audit_suspension.sql
-- ############################################################################

-- ============================================================================
-- HandzJ Digital Receipts — Migration 010
-- KYC identity (private), account status (suspend/flag), platform audit log,
-- email-or-phone login resolver, admin review RPCs.
--
-- Safe to run more than once (IF NOT EXISTS / CREATE OR REPLACE).
-- Does NOT put NIN on receipts, verify RPCs, or public surfaces.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Identity / KYC / account status on businesses
-- ---------------------------------------------------------------------------
alter table businesses add column if not exists legal_name text;
alter table businesses add column if not exists national_id text;
alter table businesses add column if not exists tin text;
alter table businesses add column if not exists kyc_status text default 'not_submitted';
alter table businesses add column if not exists kyc_submitted_at timestamptz;
alter table businesses add column if not exists kyc_reviewed_at timestamptz;
alter table businesses add column if not exists kyc_reviewer_id uuid;
alter table businesses add column if not exists kyc_rejection_reason text;
alter table businesses add column if not exists account_status text default 'active';
alter table businesses add column if not exists flagged_at timestamptz;
alter table businesses add column if not exists suspended_at timestamptz;
alter table businesses add column if not exists suspend_reason text;

-- Normalize empty kyc/account status
update businesses set kyc_status = 'not_submitted' where kyc_status is null or kyc_status = '';
update businesses set account_status = 'active' where account_status is null or account_status = '';

-- Phone unique when present (for login lookup). Multiple nulls OK.
create unique index if not exists businesses_phone_uidx
  on businesses (phone)
  where phone is not null and length(trim(phone)) > 0;

comment on column businesses.national_id is 'Private KYC only. Never expose via verify RPC, receipts, QR, or public APIs.';
comment on column businesses.kyc_status is 'not_submitted | pending | approved | rejected';
comment on column businesses.account_status is 'active | flagged | under_review | suspended | terminated';

-- ---------------------------------------------------------------------------
-- 2. business_active — also block suspended / terminated
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
      and coalesce(b.account_status, 'active') not in ('suspended', 'terminated')
      and (
        (b.subscription_status = 'active' and (b.subscribed_until is null or b.subscribed_until > now()))
        or (coalesce(b.subscription_status,'trialing') = 'trialing' and b.trial_ends_at is not null and b.trial_ends_at > now())
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. Platform audit log
-- ---------------------------------------------------------------------------
create table if not exists platform_events (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  user_id     uuid,
  business_id uuid,
  action      text not null,
  actor_id    uuid,
  actor_email text,
  receipt_id  uuid,
  result      text,
  meta        jsonb default '{}'::jsonb
);

create index if not exists platform_events_biz_idx on platform_events (business_id, created_at desc);
create index if not exists platform_events_action_idx on platform_events (action, created_at desc);

alter table platform_events enable row level security;

drop policy if exists "pe_admin_select" on platform_events;
create policy "pe_admin_select" on platform_events
  for select to authenticated
  using (public.is_platform_admin());

-- No direct insert from clients; use log_platform_event RPC
drop policy if exists "pe_no_client_insert" on platform_events;
create policy "pe_no_client_insert" on platform_events
  for insert to authenticated
  with check (false);

create or replace function public.log_platform_event(
  p_action text,
  p_business_id uuid default null,
  p_receipt_id uuid default null,
  p_result text default null,
  p_meta jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  begin
    select email into v_email from auth.users where id = auth.uid();
  exception when others then
    v_email := null;
  end;

  insert into platform_events (user_id, business_id, action, actor_id, actor_email, receipt_id, result, meta)
  values (
    auth.uid(),
    p_business_id,
    p_action,
    auth.uid(),
    v_email,
    p_receipt_id,
    p_result,
    coalesce(p_meta, '{}'::jsonb)
  );
end;
$$;

grant execute on function public.log_platform_event(text, uuid, uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Phone → email resolver for login (no SMS OTP)
-- ---------------------------------------------------------------------------
-- Returns the auth email for a business whose phone matches, if unique.
-- Does not return NIN or other KYC fields.
create or replace function public.resolve_login_email(p_identifier text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_email text;
  v_count int;
begin
  v_id := lower(trim(coalesce(p_identifier, '')));
  if length(v_id) < 3 then
    return null;
  end if;

  -- If it looks like an email, do not resolve via phone table
  if position('@' in v_id) > 0 then
    return null;
  end if;

  -- Normalize common UG phone forms: keep digits only for compare
  v_id := regexp_replace(v_id, '[^0-9+]', '', 'g');

  select count(*) into v_count
  from businesses b
  where b.phone is not null
    and (
      regexp_replace(b.phone, '[^0-9+]', '', 'g') = v_id
      or right(regexp_replace(b.phone, '[^0-9]', '', 'g'), 9)
         = right(regexp_replace(v_id, '[^0-9]', '', 'g'), 9)
    );

  if v_count <> 1 then
    return null;
  end if;

  select u.email into v_email
  from businesses b
  join auth.users u on u.id = b.owner_id
  where b.phone is not null
    and (
      regexp_replace(b.phone, '[^0-9+]', '', 'g') = v_id
      or right(regexp_replace(b.phone, '[^0-9]', '', 'g'), 9)
         = right(regexp_replace(v_id, '[^0-9]', '', 'g'), 9)
    )
  limit 1;

  return v_email;
end;
$$;

-- Callable by anon during login (before session exists)
grant execute on function public.resolve_login_email(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Merchant: submit KYC
-- ---------------------------------------------------------------------------
create or replace function public.submit_kyc(
  p_legal_name text,
  p_national_id text,
  p_tin text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid;
  nin text;
begin
  b_id := public.my_business_id();
  if b_id is null then
    raise exception 'No business for this account';
  end if;

  if length(trim(coalesce(p_legal_name, ''))) < 2 then
    raise exception 'Legal name is required';
  end if;

  nin := upper(trim(coalesce(p_national_id, '')));
  if length(nin) < 5 then
    raise exception 'National ID / NIN is required';
  end if;

  update businesses set
    legal_name = trim(p_legal_name),
    national_id = nin,
    tin = nullif(trim(coalesce(p_tin, '')), ''),
    kyc_status = 'pending',
    kyc_submitted_at = now(),
    kyc_rejection_reason = null
  where id = b_id;

  perform public.log_platform_event('KYC_SUBMITTED', b_id, null, 'pending', jsonb_build_object('has_tin', p_tin is not null and length(trim(p_tin)) > 0));

  return 'pending';
end;
$$;

grant execute on function public.submit_kyc(text, text, text) to authenticated;

-- Merchant may read own KYC status (not via open select of national_id to others)
create or replace function public.my_kyc_status()
returns table (
  kyc_status text,
  legal_name text,
  national_id_masked text,
  tin text,
  kyc_submitted_at timestamptz,
  kyc_reviewed_at timestamptz,
  kyc_rejection_reason text,
  account_status text,
  suspend_reason text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(b.kyc_status, 'not_submitted'),
    b.legal_name,
    case
      when b.national_id is null or length(b.national_id) < 4 then null
      else repeat('•', greatest(0, length(b.national_id) - 4)) || right(b.national_id, 4)
    end,
    b.tin,
    b.kyc_submitted_at,
    b.kyc_reviewed_at,
    b.kyc_rejection_reason,
    coalesce(b.account_status, 'active'),
    b.suspend_reason
  from businesses b
  where b.id = public.my_business_id();
$$;

grant execute on function public.my_kyc_status() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Admin: list KYC (masked NIN in list)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_kyc()
returns table (
  business_id uuid,
  business_name text,
  owner_email text,
  phone text,
  legal_name text,
  national_id_masked text,
  tin text,
  kyc_status text,
  kyc_submitted_at timestamptz,
  kyc_reviewed_at timestamptz,
  kyc_rejection_reason text,
  account_status text,
  suspend_reason text,
  subscription_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id,
    b.name,
    u.email,
    b.phone,
    b.legal_name,
    case
      when b.national_id is null or length(b.national_id) < 4 then null
      else repeat('•', greatest(0, length(b.national_id) - 4)) || right(b.national_id, 4)
    end,
    b.tin,
    coalesce(b.kyc_status, 'not_submitted'),
    b.kyc_submitted_at,
    b.kyc_reviewed_at,
    b.kyc_rejection_reason,
    coalesce(b.account_status, 'active'),
    b.suspend_reason,
    coalesce(b.subscription_status, 'trialing')
  from businesses b
  left join auth.users u on u.id = b.owner_id
  where public.is_platform_admin()
  order by
    case coalesce(b.kyc_status, 'not_submitted')
      when 'pending' then 0
      when 'rejected' then 1
      when 'approved' then 2
      else 3
    end,
    b.kyc_submitted_at desc nulls last;
$$;

grant execute on function public.admin_list_kyc() to authenticated;

-- Full NIN only for platform admin explicit detail call
create or replace function public.admin_get_kyc_detail(p_business uuid)
returns table (
  business_id uuid,
  business_name text,
  owner_email text,
  phone text,
  legal_name text,
  national_id text,
  tin text,
  kyc_status text,
  kyc_submitted_at timestamptz,
  kyc_reviewed_at timestamptz,
  kyc_rejection_reason text,
  account_status text,
  suspend_reason text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id, b.name, u.email, b.phone, b.legal_name, b.national_id, b.tin,
    coalesce(b.kyc_status, 'not_submitted'),
    b.kyc_submitted_at, b.kyc_reviewed_at, b.kyc_rejection_reason,
    coalesce(b.account_status, 'active'), b.suspend_reason
  from businesses b
  left join auth.users u on u.id = b.owner_id
  where public.is_platform_admin() and b.id = p_business;
$$;

grant execute on function public.admin_get_kyc_detail(uuid) to authenticated;

create or replace function public.admin_review_kyc(
  p_business uuid,
  p_decision text,
  p_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  d text;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  d := lower(trim(coalesce(p_decision, '')));
  if d not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  if d = 'rejected' and length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Rejection reason is required';
  end if;

  update businesses set
    kyc_status = d,
    kyc_reviewed_at = now(),
    kyc_reviewer_id = auth.uid(),
    kyc_rejection_reason = case when d = 'rejected' then trim(p_reason) else null end
  where id = p_business;

  perform public.log_platform_event(
    case when d = 'approved' then 'KYC_APPROVED' else 'KYC_REJECTED' end,
    p_business,
    null,
    d,
    jsonb_build_object('reason', p_reason)
  );

  return d;
end;
$$;

grant execute on function public.admin_review_kyc(uuid, text, text) to authenticated;

create or replace function public.admin_set_account_status(
  p_business uuid,
  p_status text,
  p_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  s text;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  s := lower(trim(coalesce(p_status, '')));
  if s not in ('active', 'flagged', 'under_review', 'suspended', 'terminated') then
    raise exception 'Invalid account status';
  end if;

  update businesses set
    account_status = s,
    flagged_at = case when s = 'flagged' then now() else flagged_at end,
    suspended_at = case when s in ('suspended', 'terminated') then now()
                        when s = 'active' then null
                        else suspended_at end,
    suspend_reason = case
      when s in ('flagged', 'under_review', 'suspended', 'terminated') then nullif(trim(coalesce(p_reason, '')), '')
      else null
    end
  where id = p_business;

  perform public.log_platform_event(
    case
      when s = 'suspended' then 'ACCOUNT_SUSPENDED'
      when s = 'active' then 'ACCOUNT_REACTIVATED'
      when s = 'flagged' then 'ACCOUNT_FLAGGED'
      else 'ACCOUNT_STATUS_' || upper(s)
    end,
    p_business,
    null,
    s,
    jsonb_build_object('reason', p_reason)
  );

  return s;
end;
$$;

grant execute on function public.admin_set_account_status(uuid, text, text) to authenticated;

-- Extend admin_list_businesses-compatible view of status: recreate list to include account/kyc
create or replace function public.admin_list_businesses()
returns table (
  id uuid,
  name text,
  prefix text,
  phone text,
  email text,
  owner_email text,
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
  kyc_status text,
  account_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id,
    b.name,
    b.prefix,
    b.phone,
    b.email,
    u.email as owner_email,
    b.created_at as signed_up_at,
    coalesce(b.subscription_status, 'trialing') as subscription_status,
    b.trial_ends_at,
    b.subscribed_until,
    case
      when b.subscription_status = 'active' and b.subscribed_until is not null
        then greatest(0, ceil(extract(epoch from (b.subscribed_until - now())) / 86400))::int
      when coalesce(b.subscription_status,'trialing') = 'trialing' and b.trial_ends_at is not null
        then greatest(0, ceil(extract(epoch from (b.trial_ends_at - now())) / 86400))::int
      else null
    end as days_left,
    case
      when coalesce(b.account_status, 'active') = 'suspended' then 'SUSPENDED'
      when coalesce(b.account_status, 'active') = 'terminated' then 'TERMINATED'
      when coalesce(b.account_status, 'active') = 'flagged' then 'FLAGGED'
      when coalesce(b.account_status, 'active') = 'under_review' then 'UNDER_REVIEW'
      when b.subscription_status = 'active'
       and (b.subscribed_until is null or b.subscribed_until > now()) then 'SUBSCRIBED'
      when b.subscription_status = 'active' then 'SUB_EXPIRED'
      when coalesce(b.subscription_status,'trialing') = 'trialing'
       and b.trial_ends_at > now() then 'TRIAL'
      when coalesce(b.subscription_status,'trialing') = 'trialing' then 'TRIAL_ENDED'
      else upper(coalesce(b.subscription_status, 'UNKNOWN'))
    end as state,
    count(r.id) as receipts_count,
    count(r.id) filter (where r.status = 'VALID') as receipts_valid,
    max(r.created_at) as last_receipt_at,
    coalesce(sum(r.amount) filter (where r.status = 'VALID'), 0) as total_billed,
    max(r.currency) as currency,
    coalesce(b.kyc_status, 'not_submitted') as kyc_status,
    coalesce(b.account_status, 'active') as account_status
  from businesses b
  left join auth.users u on u.id = b.owner_id
  left join receipts r on r.business_id = b.id
  where public.is_platform_admin()
  group by b.id, u.email
  order by b.created_at desc;
$$;

grant execute on function public.admin_list_businesses() to authenticated;


-- END 010_kyc_audit_suspension.sql


-- ############################################################################
-- BEGIN 011_lock_name_prefix.sql
-- ############################################################################

-- ============================================================================
-- Migration 011 — Lock business name & receipt prefix after first set
-- Merchants cannot change them via client update; platform admin uses RPC.
-- Safe to run more than once.
-- ============================================================================

-- Prevent non-admin from changing name or prefix once set
create or replace function public.businesses_lock_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Platform admins may change anything
  if public.is_platform_admin() then
    return NEW;
  end if;

  -- Prefix: once non-empty, freeze
  if OLD.prefix is not null and length(trim(OLD.prefix)) > 0 then
    if NEW.prefix is distinct from OLD.prefix then
      raise exception 'PREFIX_LOCKED: receipt prefix cannot be changed after it is set — contact HandzJ support';
    end if;
  end if;

  -- Name: once non-empty, freeze for non-admins
  if OLD.name is not null and length(trim(OLD.name)) > 0 then
    if NEW.name is distinct from OLD.name then
      raise exception 'NAME_LOCKED: business name cannot be changed after signup — contact HandzJ support to update it';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_businesses_lock_identity on businesses;
create trigger trg_businesses_lock_identity
  before update on businesses
  for each row
  execute function public.businesses_lock_identity();

-- Admin-only identity update (name and/or prefix)
create or replace function public.admin_update_business_identity(
  p_business uuid,
  p_name text default null,
  p_prefix text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text;
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  if p_name is not null and length(trim(p_name)) < 2 then
    raise exception 'Business name too short';
  end if;

  v_prefix := null;
  if p_prefix is not null then
    v_prefix := upper(regexp_replace(trim(p_prefix), '[^A-Za-z]', '', 'g'));
    v_prefix := left(v_prefix, 4);
    if length(v_prefix) < 1 then
      raise exception 'Invalid prefix';
    end if;
  end if;

  update businesses set
    name = case when p_name is not null then trim(p_name) else name end,
    prefix = case when v_prefix is not null then v_prefix else prefix end
  where id = p_business;

  if not found then
    raise exception 'Business not found';
  end if;

  perform public.log_platform_event(
    'ADMIN_IDENTITY_UPDATE',
    p_business,
    null,
    'ok',
    jsonb_build_object('name_changed', p_name is not null, 'prefix_changed', v_prefix is not null)
  );

  return 'ok';
end;
$$;

grant execute on function public.admin_update_business_identity(uuid, text, text) to authenticated;


-- END 011_lock_name_prefix.sql


-- ############################################################################
-- BEGIN 012_lock_logo.sql
-- ############################################################################

-- ============================================================================
-- Migration 012 — Logo: set once, then locked; admin may update or grant one change
-- ============================================================================

alter table businesses add column if not exists logo_change_allowed boolean default false;

update businesses set logo_change_allowed = false where logo_change_allowed is null;

-- Extend identity lock trigger to cover logo_url
create or replace function public.businesses_lock_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_platform_admin() then
    return NEW;
  end if;

  -- Prefix lock
  if OLD.prefix is not null and length(trim(OLD.prefix)) > 0 then
    if NEW.prefix is distinct from OLD.prefix then
      raise exception 'PREFIX_LOCKED: receipt prefix cannot be changed after it is set — contact HandzJ support';
    end if;
  end if;

  -- Name lock
  if OLD.name is not null and length(trim(OLD.name)) > 0 then
    if NEW.name is distinct from OLD.name then
      raise exception 'NAME_LOCKED: business name cannot be changed after signup — contact HandzJ support to update it';
    end if;
  end if;

  -- Logo lock: once a logo exists, merchant cannot change/remove unless one-time grant
  if OLD.logo_url is not null and length(trim(OLD.logo_url)) > 0 then
    if NEW.logo_url is distinct from OLD.logo_url then
      if coalesce(OLD.logo_change_allowed, false) = true then
        -- one-time change used up
        NEW.logo_change_allowed := false;
      else
        raise exception 'LOGO_LOCKED: logo cannot be changed after it is set — contact HandzJ support for a one-time update';
      end if;
    end if;
  end if;

  -- Merchant cannot set logo_change_allowed themselves
  if NEW.logo_change_allowed is distinct from OLD.logo_change_allowed then
    if not public.is_platform_admin() then
      NEW.logo_change_allowed := OLD.logo_change_allowed;
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_businesses_lock_identity on businesses;
create trigger trg_businesses_lock_identity
  before update on businesses
  for each row
  execute function public.businesses_lock_identity();

-- Admin: set logo URL directly, or grant one merchant change
create or replace function public.admin_set_logo(
  p_business uuid,
  p_logo_url text default null,
  p_grant_one_change boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Not permitted';
  end if;

  if p_grant_one_change then
    update businesses set logo_change_allowed = true where id = p_business;
    perform public.log_platform_event('LOGO_CHANGE_GRANTED', p_business, null, 'ok', '{}'::jsonb);
    return 'granted';
  end if;

  update businesses set
    logo_url = nullif(trim(coalesce(p_logo_url, '')), ''),
    logo_change_allowed = false
  where id = p_business;

  if not found then raise exception 'Business not found'; end if;

  perform public.log_platform_event(
    'ADMIN_LOGO_UPDATE',
    p_business,
    null,
    'ok',
    jsonb_build_object('cleared', p_logo_url is null or length(trim(p_logo_url)) = 0)
  );

  return 'ok';
end;
$$;

grant execute on function public.admin_set_logo(uuid, text, boolean) to authenticated;


-- END 012_lock_logo.sql


-- ############################################################################
-- BEGIN 013_rls_policies.sql
-- ############################################################################

-- ============================================================================
-- HandzJ Digital Receipts — Migration 013
-- Row Level Security: enable, harden, and document policies for all core tables.
-- Safe to run more than once.
--
-- Rules:
--   * anon: no direct table access (verification uses security definer RPCs only)
--   * authenticated: tenant-scoped via my_business_id() / roles
--   * platform admin: elevated access only through security definer RPCs
--   * NIN / KYC / platform_events: never public
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Ensure helper functions exist (no-op replace if already present)
-- ---------------------------------------------------------------------------
-- my_business_id, my_role, my_branch_id, business_active, is_platform_admin
-- are defined in earlier migrations. This file only adjusts policies.

-- ---------------------------------------------------------------------------
-- 1. Enable RLS on every application table
-- ---------------------------------------------------------------------------
alter table if exists businesses          enable row level security;
alter table if exists receipts            enable row level security;
alter table if exists receipt_sequences   enable row level security;
alter table if exists receipt_events      enable row level security;
alter table if exists branches            enable row level security;
alter table if exists memberships         enable row level security;
alter table if exists platform_admins     enable row level security;
alter table if exists platform_events     enable row level security;

-- Optional: force RLS for table owners in Supabase (postgres still bypasses;
-- authenticated role does not).
alter table if exists businesses          force row level security;
alter table if exists receipts            force row level security;
alter table if exists receipt_sequences   force row level security;
alter table if exists receipt_events      force row level security;
alter table if exists branches            force row level security;
alter table if exists memberships         force row level security;
alter table if exists platform_admins     force row level security;
alter table if exists platform_events     force row level security;

-- ---------------------------------------------------------------------------
-- 2. businesses
--    Owner: full select/insert/update of own row
--    Staff (active membership): select only (for branding/settings read)
--    No delete for clients
--    Name/prefix/logo still protected by triggers (011/012)
-- ---------------------------------------------------------------------------
drop policy if exists "biz_select" on businesses;
drop policy if exists "biz_insert" on businesses;
drop policy if exists "biz_update" on businesses;
drop policy if exists "biz_owner_select" on businesses;
drop policy if exists "biz_owner_insert" on businesses;
drop policy if exists "biz_owner_update" on businesses;
drop policy if exists "biz_member_select" on businesses;
drop policy if exists "biz_owner_delete" on businesses;

create policy "biz_owner_select" on businesses
  for select to authenticated
  using (
    owner_id = auth.uid()
    or id = public.my_business_id()
  );

create policy "biz_owner_insert" on businesses
  for insert to authenticated
  with check (owner_id = auth.uid());

create policy "biz_owner_update" on businesses
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- No DELETE policy → merchants cannot drop the business row via the API

-- ---------------------------------------------------------------------------
-- 3. receipts
--    Select/insert: tenant + branch rules (from 009)
--    Update: none for clients (void via void_receipt RPC)
--    Delete: none
-- ---------------------------------------------------------------------------
drop policy if exists "rcp_select" on receipts;
drop policy if exists "rcp_insert" on receipts;
drop policy if exists "rcp_update" on receipts;
drop policy if exists "rcp_owner_select" on receipts;
drop policy if exists "rcp_owner_insert" on receipts;
drop policy if exists "rcp_owner_update" on receipts;
drop policy if exists "rcp_member_select" on receipts;
drop policy if exists "rcp_member_insert" on receipts;
drop policy if exists "rcp_member_update" on receipts;
drop policy if exists "rcp_delete" on receipts;

create policy "rcp_member_select" on receipts
  for select to authenticated
  using (
    business_id = public.my_business_id()
    and (
      public.my_role() in ('owner', 'manager')
      or public.my_branch_id() is null
      or branch_id is null
      or branch_id = public.my_branch_id()
    )
  );

create policy "rcp_member_insert" on receipts
  for insert to authenticated
  with check (
    business_id = public.my_business_id()
    and public.business_active(business_id)
    and (
      branch_id is null
      or exists (
        select 1 from branches br
        where br.id = branch_id and br.business_id = business_id
      )
    )
    and (
      public.my_role() in ('owner', 'manager')
      or public.my_branch_id() is null
      or branch_id is null
      or branch_id = public.my_branch_id()
    )
  );

-- No UPDATE / DELETE policies for authenticated → void_receipt() only

-- ---------------------------------------------------------------------------
-- 4. receipt_sequences — select own tenant; writes only via security definer
-- ---------------------------------------------------------------------------
drop policy if exists "seq_all" on receipt_sequences;
drop policy if exists "seq_owner" on receipt_sequences;
drop policy if exists "seq_member_select" on receipt_sequences;

create policy "seq_member_select" on receipt_sequences
  for select to authenticated
  using (business_id = public.my_business_id());

-- No insert/update/delete for clients

-- ---------------------------------------------------------------------------
-- 5. receipt_events — owner/member select; writes via triggers/RPCs only
-- ---------------------------------------------------------------------------
drop policy if exists "re_owner_select" on receipt_events;
drop policy if exists "re_member_select" on receipt_events;

create policy "re_member_select" on receipt_events
  for select to authenticated
  using (business_id = public.my_business_id());

-- No insert/update/delete for clients

-- ---------------------------------------------------------------------------
-- 6. branches
-- ---------------------------------------------------------------------------
drop policy if exists "br_select" on branches;
drop policy if exists "br_write" on branches;
drop policy if exists "br_member_select" on branches;
drop policy if exists "br_manager_write" on branches;

create policy "br_member_select" on branches
  for select to authenticated
  using (business_id = public.my_business_id());

create policy "br_manager_write" on branches
  for all to authenticated
  using (
    business_id = public.my_business_id()
    and public.my_role() in ('owner', 'manager')
  )
  with check (
    business_id = public.my_business_id()
    and public.my_role() in ('owner', 'manager')
  );

-- ---------------------------------------------------------------------------
-- 7. memberships
-- ---------------------------------------------------------------------------
drop policy if exists "mem_select" on memberships;
drop policy if exists "mem_owner_write" on memberships;
drop policy if exists "mem_member_select" on memberships;
drop policy if exists "mem_owner_write2" on memberships;

create policy "mem_member_select" on memberships
  for select to authenticated
  using (
    business_id = public.my_business_id()
    or user_id = auth.uid()
  );

create policy "mem_owner_write" on memberships
  for all to authenticated
  using (
    business_id = public.my_business_id()
    and public.my_role() = 'owner'
  )
  with check (
    business_id = public.my_business_id()
    and public.my_role() = 'owner'
  );

-- ---------------------------------------------------------------------------
-- 8. platform_admins — no direct client policies
--    Reads only via is_platform_admin() / admin_* security definer RPCs
-- ---------------------------------------------------------------------------
drop policy if exists "pa_select" on platform_admins;
drop policy if exists "pa_all" on platform_admins;
-- Intentionally zero policies for authenticated/anon

-- ---------------------------------------------------------------------------
-- 9. platform_events — admin select only; no client insert
-- ---------------------------------------------------------------------------
drop policy if exists "pe_admin_select" on platform_events;
drop policy if exists "pe_no_client_insert" on platform_events;
drop policy if exists "pe_select" on platform_events;

create policy "pe_admin_select" on platform_events
  for select to authenticated
  using (public.is_platform_admin());

-- No insert/update/delete policies → log_platform_event() (security definer) only

-- ---------------------------------------------------------------------------
-- 10. Revoke broad grants if present (Supabase often grants ALL to authenticated)
--     Re-grant only the operations policies allow
-- ---------------------------------------------------------------------------
do $$
begin
  -- businesses
  revoke all on table businesses from anon;
  grant select, insert, update on table businesses to authenticated;

  -- receipts
  revoke all on table receipts from anon;
  grant select, insert on table receipts to authenticated;
  -- update/delete not granted to authenticated

  -- receipt_sequences
  revoke all on table receipt_sequences from anon;
  grant select on table receipt_sequences to authenticated;

  -- receipt_events
  if to_regclass('public.receipt_events') is not null then
    revoke all on table receipt_events from anon;
    grant select on table receipt_events to authenticated;
  end if;

  -- branches
  if to_regclass('public.branches') is not null then
    revoke all on table branches from anon;
    grant select, insert, update, delete on table branches to authenticated;
  end if;

  -- memberships
  if to_regclass('public.memberships') is not null then
    revoke all on table memberships from anon;
    grant select, insert, update, delete on table memberships to authenticated;
  end if;

  -- platform_admins
  if to_regclass('public.platform_admins') is not null then
    revoke all on table platform_admins from anon, authenticated;
  end if;

  -- platform_events
  if to_regclass('public.platform_events') is not null then
    revoke all on table platform_events from anon;
    grant select on table platform_events to authenticated; -- filtered by pe_admin_select
  end if;
exception when others then
  raise notice 'Grant/revoke partial: %', SQLERRM;
end $$;

-- ---------------------------------------------------------------------------
-- 11. Verification
--     Public verify uses verify_receipt RPC (security definer) — not table SELECT.
--     Confirm: no policy grants anon SELECT on receipts or businesses.
-- ---------------------------------------------------------------------------

comment on table businesses is 'RLS: owner insert/update; owner or member select; no client delete';
comment on table receipts is 'RLS: member select/insert with branch rules; void via RPC only; no client delete';
comment on table platform_events is 'RLS: platform admin select only; writes via log_platform_event';


-- END 013_rls_policies.sql
