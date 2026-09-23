-- ============================================================================
-- HandzJ Digital Receipts — Migration 024
-- Business Verification admin surface.
--
-- This is NOT a new verification mechanism. It widens the existing KYC/
-- account-status review RPCs from migration 010 so Platform Admin gets a
-- proper "Business Verification" queue: who is pending, whether their EMAIL
-- is confirmed (from auth.users — the existing source, no second mechanism),
-- their branch/registration details, and how long they've been waiting.
--
-- Receipt verification (valid/voided/not found) is untouched — see 013/023.
--
-- Safe to run more than once (CREATE OR REPLACE / IF NOT EXISTS).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Admin: verification queue list
--    Adds: email confirmation (from auth.users, existing source), signup
--    date, category, and the business's primary branch — on top of the
--    existing masked-KYC list from migration 010.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_list_kyc();

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
  subscription_status text,
  email_confirmed boolean,
  signed_up_at timestamptz,
  category text,
  branch_name text,
  branch_address text
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
    coalesce(b.subscription_status, 'trialing'),
    (u.email_confirmed_at is not null),
    b.created_at,
    b.category,
    br.name,
    br.address
  from businesses b
  left join auth.users u on u.id = b.owner_id
  left join lateral (
    select br1.name, br1.address
    from branches br1
    where br1.business_id = b.id
    order by br1.created_at asc
    limit 1
  ) br on true
  where public.is_platform_admin()
  order by
    -- Businesses waiting on the platform (registered, nothing decided yet)
    -- surface first; email-confirmed-but-undecided next; decided last.
    case coalesce(b.kyc_status, 'not_submitted')
      when 'rejected' then 0
      when 'pending' then 0
      when 'not_submitted' then
        case when u.email_confirmed_at is not null then 0 else 1 end
      when 'approved' then 2
      else 3
    end,
    b.created_at asc;
$$;

grant execute on function public.admin_list_kyc() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Admin: single-business verification review detail
--    Same widening as above, plus every branch (not just the primary one)
--    and the full (unmasked) submission fields already covered by 010.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_get_kyc_detail(uuid);

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
  suspend_reason text,
  email_confirmed boolean,
  signed_up_at timestamptz,
  category text,
  tagline text,
  whatsapp text,
  branches text
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
    coalesce(b.account_status, 'active'), b.suspend_reason,
    (u.email_confirmed_at is not null),
    b.created_at,
    b.category,
    b.tagline,
    b.whatsapp,
    (
      select string_agg(
        trim(br.name) || coalesce(' — ' || nullif(trim(br.address), ''), ''),
        E'\n' order by br.created_at asc
      )
      from branches br
      where br.business_id = b.id
    )
  from businesses b
  left join auth.users u on u.id = b.owner_id
  where public.is_platform_admin() and b.id = p_business;
$$;

grant execute on function public.admin_get_kyc_detail(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Admin: pending-verification count, for the dashboard badge
--    ("Business Verification — N Pending"). Pending = not yet decided
--    (kyc_status not in approved/rejected) and not already suspended/
--    terminated — a suspended account doesn't need a verification nudge.
-- ---------------------------------------------------------------------------
create or replace function public.admin_verification_pending_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)
  from businesses b
  where public.is_platform_admin()
    and coalesce(b.kyc_status, 'not_submitted') not in ('approved', 'rejected')
    and coalesce(b.account_status, 'active') not in ('suspended', 'terminated');
$$;

grant execute on function public.admin_verification_pending_count() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. "Start review" is just the existing under_review account status
--    (migration 010's admin_set_account_status already allows it) — no new
--    status machinery needed. Nothing to add here; noted for clarity.
-- ---------------------------------------------------------------------------

-- END 024_business_verification.sql
