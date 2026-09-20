-- ============================================================================
-- VERIFY_009_SECURITY.sql
-- Read-only checks after applying 009_security_hardening.sql
-- Supabase → SQL Editor → paste → Run
-- Does NOT change data. Does NOT create a migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- A. Objects from 008 / 009 present?
-- ---------------------------------------------------------------------------
select 'A1 tables' as check_id,
  (to_regclass('public.branches') is not null) as branches_ok,
  (to_regclass('public.memberships') is not null) as memberships_ok,
  (to_regclass('public.receipts') is not null) as receipts_ok,
  (to_regclass('public.receipt_sequences') is not null) as sequences_ok;

select 'A2 receipt columns' as check_id, column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'receipts'
  and column_name in (
    'branch_id','issued_by','issued_by_name','lines','verify_id','status','business_id'
  )
order by column_name;

select 'A3 functions' as check_id, p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'my_business_id','my_role','my_branch_id','can_void','can_manage_staff',
    'void_receipt','verify_receipt','next_receipt_no','business_active',
    'invite_staff','create_branch','list_my_staff','list_my_branches'
  )
order by p.proname;

-- ---------------------------------------------------------------------------
-- B. Triggers (immutability, branch guard, issuer stamp)
-- ---------------------------------------------------------------------------
select 'B1 triggers' as check_id, tgname as trigger_name, tgrelid::regclass as on_table
from pg_trigger
where not tgisinternal
  and tgrelid = 'public.receipts'::regclass
  and tgname in (
    'trg_receipts_immutability',
    'trg_receipts_branch_guard',
    'trg_receipts_stamp_issuer',
    'trg_receipts_log_issued'
  )
order by tgname;

-- ---------------------------------------------------------------------------
-- C. RLS enabled?
-- ---------------------------------------------------------------------------
select 'C1 rls' as check_id, c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('receipts','businesses','branches','memberships','receipt_sequences')
order by c.relname;

-- ---------------------------------------------------------------------------
-- D. Policies on receipts (critical after 009)
-- ---------------------------------------------------------------------------
select 'D1 receipt policies' as check_id,
  pol.polname as policy_name,
  case pol.polcmd
    when 'r' then 'SELECT'
    when 'a' then 'INSERT'
    when 'w' then 'UPDATE'
    when 'd' then 'DELETE'
    when '*' then 'ALL'
  end as command
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'receipts'
order by pol.polname;

-- EXPECT after 009:
--   SELECT policy present (rcp_member_select or similar)
--   INSERT policy present
--   NO UPDATE policy (void only via RPC)
--   NO DELETE policy

select 'D2 update_policy_absent' as check_id,
  not exists (
    select 1
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'receipts'
      and pol.polcmd = 'w'  -- UPDATE
  ) as no_client_update_policy_ok;

select 'D3 legacy_rcp_owner_update_gone' as check_id,
  not exists (
    select 1
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'receipts'
      and pol.polname = 'rcp_owner_update'
  ) as legacy_update_policy_removed_ok;

-- ---------------------------------------------------------------------------
-- E. Policies on branches / memberships
-- ---------------------------------------------------------------------------
select 'E1 branch policies' as check_id, pol.polname, 
  case pol.polcmd when 'r' then 'SELECT' when 'a' then 'INSERT' when 'w' then 'UPDATE' when 'd' then 'DELETE' when '*' then 'ALL' end as cmd
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'branches'
order by pol.polname;

select 'E2 membership policies' as check_id, pol.polname,
  case pol.polcmd when 'r' then 'SELECT' when 'a' then 'INSERT' when 'w' then 'UPDATE' when 'd' then 'DELETE' when '*' then 'ALL' end as cmd
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'memberships'
order by pol.polname;

-- ---------------------------------------------------------------------------
-- F. Sequence model (business-wide, not branch-wide)
-- ---------------------------------------------------------------------------
select 'F1 sequence_pk' as check_id, tc.constraint_name, kcu.column_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
 and tc.table_schema = kcu.table_schema
where tc.table_schema = 'public'
  and tc.table_name = 'receipt_sequences'
  and tc.constraint_type = 'PRIMARY KEY'
order by kcu.ordinal_position;
-- Expect columns: business_id, year  (NOT branch_id)

-- ---------------------------------------------------------------------------
-- G. Data snapshot (counts only — no secrets)
-- ---------------------------------------------------------------------------
select 'G1 counts' as check_id,
  (select count(*) from businesses) as businesses,
  (select count(*) from branches) as branches,
  (select count(*) from memberships) as memberships,
  (select count(*) from receipts) as receipts,
  (select count(*) from receipts where status = 'VALID') as valid_receipts,
  (select count(*) from receipts where status = 'VOIDED') as voided_receipts;

select 'G2 membership_roles' as check_id, role, count(*) as n, count(*) filter (where active) as active_n
from memberships
group by role
order by role;

select 'G3 branches_per_business' as check_id, b.name as business, count(br.id) as branch_count
from businesses b
left join branches br on br.business_id = b.id
group by b.id, b.name
order by branch_count desc
limit 20;

-- ---------------------------------------------------------------------------
-- H. Orphan / integrity checks
-- ---------------------------------------------------------------------------
select 'H1 receipt_branch_orphan' as check_id, count(*) as bad_rows
from receipts r
where r.branch_id is not null
  and not exists (
    select 1 from branches br
    where br.id = r.branch_id and br.business_id = r.business_id
  );
-- Expect: 0

select 'H2 duplicate_receipt_numbers' as check_id, business_id, receipt_no, count(*) as n
from receipts
group by business_id, receipt_no
having count(*) > 1;
-- Expect: 0 rows

-- ---------------------------------------------------------------------------
-- I. PASS / FAIL summary (boolean scorecard)
-- ---------------------------------------------------------------------------
with score as (
  select
    (to_regclass('public.branches') is not null
     and to_regclass('public.memberships') is not null) as tables_008_ok,
    exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'void_receipt'
    ) as void_rpc_ok,
    exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'verify_receipt'
    ) as verify_rpc_ok,
    exists (
      select 1 from pg_trigger
      where not tgisinternal and tgname = 'trg_receipts_branch_guard'
    ) as branch_guard_ok,
    exists (
      select 1 from pg_trigger
      where not tgisinternal and tgname = 'trg_receipts_stamp_issuer'
    ) as stamp_issuer_ok,
    exists (
      select 1 from pg_trigger
      where not tgisinternal and tgname = 'trg_receipts_immutability'
    ) as immutability_ok,
    not exists (
      select 1
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'receipts' and pol.polcmd = 'w'
    ) as no_update_policy_ok,
    not exists (
      select 1
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'receipts'
        and pol.polname = 'rcp_owner_update'
    ) as legacy_update_removed_ok,
    (
      select count(*) from receipts r
      where r.branch_id is not null
        and not exists (
          select 1 from branches br
          where br.id = r.branch_id and br.business_id = r.business_id
        )
    ) = 0 as no_orphan_branches_ok
)
select 'SCORECARD' as check_id,
  tables_008_ok,
  void_rpc_ok,
  verify_rpc_ok,
  branch_guard_ok,
  stamp_issuer_ok,
  immutability_ok,
  no_update_policy_ok,
  legacy_update_removed_ok,
  no_orphan_branches_ok,
  (
    tables_008_ok and void_rpc_ok and verify_rpc_ok
    and branch_guard_ok and stamp_issuer_ok and immutability_ok
    and no_update_policy_ok and legacy_update_removed_ok
    and no_orphan_branches_ok
  ) as all_critical_checks_pass
from score;

-- ---------------------------------------------------------------------------
-- How to read results
-- ---------------------------------------------------------------------------
-- SCORECARD.all_critical_checks_pass = true  → 009 structural checks OK
-- no_update_policy_ok = false               → client UPDATE still possible (009 not applied fully)
-- branch_guard_ok = false                   → re-run 009
-- H1 bad_rows > 0                           → clean orphan branch_ids manually
