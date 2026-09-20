-- ============================================================================
-- Migration 009 — Security hardening (P0/P1 from audit)
-- Depends on: 002, 005, 008
-- Safe to re-run. Does not destroy data.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- P0: Void ONLY via void_receipt() RPC — remove client UPDATE on receipts
-- ---------------------------------------------------------------------------
drop policy if exists "rcp_owner_update" on receipts;
-- No UPDATE policy for authenticated → only security definer functions can update.

-- ---------------------------------------------------------------------------
-- P0/P1: Branch-aware SELECT and INSERT
-- Owner/manager: all branches in tenant
-- Cashier with branch_id set: only that branch (and null-branch legacy rows)
-- ---------------------------------------------------------------------------
drop policy if exists "rcp_owner_select" on receipts;
drop policy if exists "rcp_member_select" on receipts;

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

drop policy if exists "rcp_owner_insert" on receipts;
drop policy if exists "rcp_member_insert" on receipts;

create policy "rcp_member_insert" on receipts
  for insert to authenticated
  with check (
    business_id = public.my_business_id()
    and public.business_active(business_id)
    -- branch must belong to this business (or be null)
    and (
      branch_id is null
      or exists (
        select 1 from branches br
        where br.id = branch_id and br.business_id = business_id
      )
    )
    -- cashiers locked to their assigned branch when set
    and (
      public.my_role() in ('owner', 'manager')
      or public.my_branch_id() is null
      or branch_id is null
      or branch_id = public.my_branch_id()
    )
  );

-- ---------------------------------------------------------------------------
-- P1: Prevent cross-tenant branch reference on any receipt write path
-- ---------------------------------------------------------------------------
create or replace function public.receipts_branch_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.branch_id is not null then
    if not exists (
      select 1 from branches br
      where br.id = NEW.branch_id and br.business_id = NEW.business_id
    ) then
      raise exception 'INVALID_BRANCH: branch does not belong to this business';
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_receipts_branch_guard on receipts;
create trigger trg_receipts_branch_guard
  before insert or update on receipts
  for each row
  execute function public.receipts_branch_guard();

-- ---------------------------------------------------------------------------
-- P1: Extend immutability to newer columns (lines, branch, issuer)
-- ---------------------------------------------------------------------------
create or replace function public.receipts_immutability_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE' and OLD.status = 'VALID' then
    -- Allowed void path: VALID → VOIDED with void metadata only
    if NEW.status = 'VOIDED' and OLD.status = 'VALID' then
      if NEW.receipt_no  is distinct from OLD.receipt_no
         or NEW.verify_id   is distinct from OLD.verify_id
         or NEW.kind        is distinct from OLD.kind
         or NEW.customer    is distinct from OLD.customer
         or NEW.cust_email  is distinct from OLD.cust_email
         or NEW.cust_phone  is distinct from OLD.cust_phone
         or NEW.item        is distinct from OLD.item
         or NEW.pkg         is distinct from OLD.pkg
         or NEW.period      is distinct from OLD.period
         or NEW.proj_ref    is distinct from OLD.proj_ref
         or NEW.description is distinct from OLD.description
         or NEW.amount      is distinct from OLD.amount
         or NEW.currency    is distinct from OLD.currency
         or NEW.method      is distinct from OLD.method
         or NEW.txn         is distinct from OLD.txn
         or NEW.paid_on     is distinct from OLD.paid_on
         or NEW.received_by is distinct from OLD.received_by
         or NEW.notes       is distinct from OLD.notes
         or NEW.created_at  is distinct from OLD.created_at
         or NEW.business_id is distinct from OLD.business_id
         or NEW.branch_id   is distinct from OLD.branch_id
         or NEW.issued_by   is distinct from OLD.issued_by
         or NEW.issued_by_name is distinct from OLD.issued_by_name
         or NEW.lines       is distinct from OLD.lines
      then
        raise exception 'IMMUTABLE: only status/void metadata may change when voiding';
      end if;
      return NEW;
    end if;

    if OLD.status = 'VOIDED' then
      raise exception 'IMMUTABLE: voided receipts cannot be changed';
    end if;

    raise exception 'IMMUTABLE: issued receipts cannot be edited — void and re-issue if needed';
  end if;
  return NEW;
end;
$$;

-- ---------------------------------------------------------------------------
-- P1: Stamp issuer on insert if client omitted (defense in depth)
-- ---------------------------------------------------------------------------
create or replace function public.receipts_stamp_issuer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.issued_by is null then
    NEW.issued_by := auth.uid();
  end if;
  if NEW.issued_by_name is null or length(trim(NEW.issued_by_name)) = 0 then
    begin
      select email into NEW.issued_by_name from auth.users where id = auth.uid();
    exception when others then
      NEW.issued_by_name := 'staff';
    end;
  end if;
  -- Force business_id to membership scope (ignore client spoof)
  if public.my_business_id() is not null then
    NEW.business_id := public.my_business_id();
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_receipts_stamp_issuer on receipts;
create trigger trg_receipts_stamp_issuer
  before insert on receipts
  for each row
  execute function public.receipts_stamp_issuer();

-- ---------------------------------------------------------------------------
-- Ensure void_receipt remains the only void path (re-assert role check)
-- ---------------------------------------------------------------------------
create or replace function public.void_receipt(p_receipt_no text, p_reason text)
returns receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  r receipts;
  b_id uuid := public.my_business_id();
begin
  if b_id is null then
    raise exception 'Not signed in to a business';
  end if;
  if not public.can_void() then
    raise exception 'Only the owner or a manager can void receipts';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'A void reason is required';
  end if;

  select * into r from receipts
  where business_id = b_id and receipt_no = p_receipt_no
  for update;

  if not found then
    raise exception 'Receipt not found';
  end if;
  if r.status = 'VOIDED' then
    raise exception 'Receipt is already voided';
  end if;

  -- Branch-scoped managers/cashiers: managers void any; if we later restrict managers by branch, add here
  update receipts set
    status = 'VOIDED',
    voided_at = now(),
    void_reason = trim(p_reason)
  where id = r.id
  returning * into r;

  begin
    insert into receipt_events (receipt_id, business_id, receipt_no, event_type, actor_id, actor_email, detail)
    values (
      r.id, r.business_id, r.receipt_no, 'VOIDED', auth.uid(),
      (select email from auth.users where id = auth.uid()),
      jsonb_build_object('reason', trim(p_reason))
    );
  exception when undefined_table then
    null;
  when others then
    null;
  end;

  return r;
end;
$$;

grant execute on function public.void_receipt(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Numbering model (documentation comment in DB)
-- BUSINESS-WIDE: one sequence per (business_id, year). Not per branch.
-- ---------------------------------------------------------------------------
comment on table receipt_sequences is
  'Business-wide receipt counters: one seq per (business_id, year). Branch does not get its own sequence.';
