-- Phase 3: receipt immutability + minimal audit trail
-- Safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Minimal audit trail (document integrity, not ERP)
-- ---------------------------------------------------------------------------
create table if not exists receipt_events (
  id            uuid primary key default gen_random_uuid(),
  receipt_id    uuid references receipts(id) on delete cascade,
  business_id   uuid not null references businesses(id) on delete cascade,
  receipt_no    text not null,
  event_type    text not null check (event_type in ('ISSUED', 'VOIDED')),
  actor_id      uuid,                          -- auth.users.id when known
  actor_email   text,
  reason        text,                          -- required for VOIDED in RPC
  details       jsonb default null,
  created_at    timestamptz not null default now()
);

create index if not exists receipt_events_receipt_idx on receipt_events(receipt_id);
create index if not exists receipt_events_business_idx on receipt_events(business_id);
create index if not exists receipt_events_no_idx on receipt_events(receipt_no);

alter table receipt_events enable row level security;

drop policy if exists "re_owner_select" on receipt_events;
create policy "re_owner_select" on receipt_events
  for select to authenticated
  using (business_id = public.my_business_id());
-- no insert/update/delete for clients — only security definer RPCs write

-- ---------------------------------------------------------------------------
-- 2. Trigger: block silent mutation of issued receipt identity fields
--    Allowed transitions:
--      • insert (new issue)
--      • VALID → VOIDED (status, voided_at, void_reason only)
--    Everything else is rejected.
-- ---------------------------------------------------------------------------
create or replace function public.receipts_immutability_guard()
returns trigger
language plpgsql
as $$
begin
  if TG_OP = 'UPDATE' then
    -- Once VOIDED, freeze completely
    if OLD.status = 'VOIDED' then
      raise exception 'IMMUTABLE: voided receipts cannot be changed';
    end if;

    -- Only allowed transition: VALID → VOIDED, and only void metadata may change
    if NEW.status = 'VOIDED' and OLD.status = 'VALID' then
      if NEW.business_id is distinct from OLD.business_id
         or NEW.receipt_no  is distinct from OLD.receipt_no
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
      then
        raise exception 'IMMUTABLE: only status/void metadata may change when voiding';
      end if;
      return NEW;
    end if;

    -- Any other field change on a VALID row is blocked
    raise exception 'IMMUTABLE: issued receipts cannot be edited — void and re-issue if needed';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_receipts_immutability on receipts;
create trigger trg_receipts_immutability
  before update on receipts
  for each row
  execute function public.receipts_immutability_guard();

-- ---------------------------------------------------------------------------
-- 3. Trigger: log ISSUED on insert
-- ---------------------------------------------------------------------------
create or replace function public.receipts_log_issued()
returns trigger
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

  insert into receipt_events (receipt_id, business_id, receipt_no, event_type, actor_id, actor_email)
  values (NEW.id, NEW.business_id, NEW.receipt_no, 'ISSUED', auth.uid(), v_email);

  return NEW;
end;
$$;

drop trigger if exists trg_receipts_log_issued on receipts;
create trigger trg_receipts_log_issued
  after insert on receipts
  for each row
  execute function public.receipts_log_issued();

-- ---------------------------------------------------------------------------
-- 4. Authorized void RPC — sole path for voiding (sets void fields + audit)
-- ---------------------------------------------------------------------------
create or replace function public.void_receipt(p_receipt_no text, p_reason text)
returns receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid;
  r receipts;
  v_email text;
begin
  b_id := public.my_business_id();
  if b_id is null then
    raise exception 'No business for this account';
  end if;

  if p_reason is null or length(trim(p_reason)) < 2 then
    raise exception 'A void reason is required';
  end if;

  select * into r
    from receipts
   where business_id = b_id
     and receipt_no = p_receipt_no
   for update;

  if not found then
    raise exception 'Receipt not found';
  end if;

  if r.status = 'VOIDED' then
    raise exception 'Receipt is already voided';
  end if;

  update receipts
     set status = 'VOIDED',
         voided_at = now(),
         void_reason = trim(p_reason)
   where id = r.id
  returning * into r;

  begin
    select email into v_email from auth.users where id = auth.uid();
  exception when others then
    v_email := null;
  end;

  insert into receipt_events (receipt_id, business_id, receipt_no, event_type, actor_id, actor_email, reason)
  values (r.id, r.business_id, r.receipt_no, 'VOIDED', auth.uid(), v_email, trim(p_reason));

  return r;
end;
$$;

grant execute on function public.void_receipt(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Tighten RLS: remove broad client UPDATE on receipts
--    Voiding goes through void_receipt() (security definer).
--    Insert remains for new issues only.
-- ---------------------------------------------------------------------------
drop policy if exists "rcp_owner_update" on receipts;
-- No client UPDATE policy. Attempted updates fail with RLS denial;
-- the immutability trigger is a second line of defence for any definer path.

comment on table receipt_events is
  'Minimal document audit: ISSUED and VOIDED only. Not a general activity log.';
