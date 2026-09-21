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
