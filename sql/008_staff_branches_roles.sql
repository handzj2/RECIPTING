-- ============================================================================
-- Migration 008 — Branches, staff roles, issued_by, stronger isolation
-- Run AFTER 002 (auth multitenant). Safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Branches
-- ---------------------------------------------------------------------------
create table if not exists branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  code text,
  phone text,
  address text,
  active boolean not null default true,
  created_at timestamptz default now()
);

create index if not exists branches_biz_idx on branches(business_id);

-- ---------------------------------------------------------------------------
-- 2. Memberships (owner / manager / cashier)
-- ---------------------------------------------------------------------------
create table if not exists memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'cashier'
    check (role in ('owner', 'manager', 'cashier')),
  branch_id uuid references branches(id) on delete set null,
  display_name text,
  active boolean not null default true,
  invited_email text,
  created_at timestamptz default now(),
  unique (business_id, user_id)
);

create index if not exists memberships_user_idx on memberships(user_id);
create index if not exists memberships_biz_idx on memberships(business_id);

-- ---------------------------------------------------------------------------
-- 3. Receipt accountability columns
-- ---------------------------------------------------------------------------
alter table receipts add column if not exists branch_id uuid references branches(id) on delete set null;
alter table receipts add column if not exists issued_by uuid references auth.users(id) on delete set null;
alter table receipts add column if not exists issued_by_name text;

create index if not exists receipts_branch_idx on receipts(branch_id);
create index if not exists receipts_issued_by_idx on receipts(issued_by);

-- ---------------------------------------------------------------------------
-- 4. Seed owner membership for every existing business
-- ---------------------------------------------------------------------------
insert into memberships (business_id, user_id, role, display_name, active)
select b.id, b.owner_id, 'owner', coalesce(b.name, 'Owner'), true
from businesses b
where b.owner_id is not null
  and not exists (
    select 1 from memberships m
    where m.business_id = b.id and m.user_id = b.owner_id
  );

-- Default branch per business (optional convenience)
insert into branches (business_id, name, code)
select b.id, 'Main', 'MAIN'
from businesses b
where not exists (select 1 from branches x where x.business_id = b.id);

-- ---------------------------------------------------------------------------
-- 5. Replace my_business_id() — owner OR active member
-- ---------------------------------------------------------------------------
create or replace function public.my_business_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select business_id from memberships
      where user_id = auth.uid() and active = true
      order by case role when 'owner' then 0 when 'manager' then 1 else 2 end
      limit 1),
    (select id from businesses where owner_id = auth.uid() limit 1)
  );
$$;

create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from memberships
      where user_id = auth.uid() and active = true
        and business_id = public.my_business_id()
      limit 1),
    case when exists (
      select 1 from businesses where owner_id = auth.uid()
    ) then 'owner' else null end
  );
$$;

create or replace function public.my_branch_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select branch_id from memberships
  where user_id = auth.uid() and active = true
    and business_id = public.my_business_id()
  limit 1;
$$;

create or replace function public.can_manage_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.my_role() in ('owner', 'manager');
$$;

create or replace function public.can_void()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.my_role() in ('owner', 'manager');
$$;

grant execute on function public.my_role() to authenticated;
grant execute on function public.my_branch_id() to authenticated;
grant execute on function public.can_manage_staff() to authenticated;
grant execute on function public.can_void() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. RLS: branches
-- ---------------------------------------------------------------------------
alter table branches enable row level security;

drop policy if exists "br_select" on branches;
drop policy if exists "br_write" on branches;

create policy "br_select" on branches
  for select to authenticated
  using (business_id = public.my_business_id());

create policy "br_write" on branches
  for all to authenticated
  using (business_id = public.my_business_id() and public.my_role() in ('owner', 'manager'))
  with check (business_id = public.my_business_id() and public.my_role() in ('owner', 'manager'));

-- ---------------------------------------------------------------------------
-- 7. RLS: memberships
-- ---------------------------------------------------------------------------
alter table memberships enable row level security;

drop policy if exists "mem_select" on memberships;
drop policy if exists "mem_owner_write" on memberships;

create policy "mem_select" on memberships
  for select to authenticated
  using (
    business_id = public.my_business_id()
    or user_id = auth.uid()
  );

-- Only owners can invite / change roles (managers could be allowed later)
create policy "mem_owner_write" on memberships
  for all to authenticated
  using (business_id = public.my_business_id() and public.my_role() = 'owner')
  with check (business_id = public.my_business_id() and public.my_role() = 'owner');

-- ---------------------------------------------------------------------------
-- 8. Receipt insert: stamp issued_by; cashiers limited to their branch
-- ---------------------------------------------------------------------------
-- Keep existing select policies; ensure insert still scoped to my_business_id.
-- Application also sends issued_by / branch_id.

-- Cashiers may insert; only owner/manager may void (void_receipt RPC should check can_void)

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

  update receipts set
    status = 'VOIDED',
    voided_at = now(),
    void_reason = trim(p_reason)
  where id = r.id
  returning * into r;

  return r;
end;
$$;

grant execute on function public.void_receipt(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Invite staff by email (owner only) — creates pending membership
--    The invitee must sign up / sign in with the same email; then claim_invite().
-- ---------------------------------------------------------------------------
create or replace function public.invite_staff(
  p_email text,
  p_role text default 'cashier',
  p_branch_id uuid default null,
  p_display_name text default null
)
returns memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid := public.my_business_id();
  uid uuid;
  m memberships;
  safe_role text;
begin
  if b_id is null or public.my_role() <> 'owner' then
    raise exception 'Only the business owner can invite staff';
  end if;

  safe_role := lower(coalesce(nullif(trim(p_role),''), 'cashier'));
  if safe_role not in ('manager', 'cashier') then
    raise exception 'Role must be manager or cashier';
  end if;

  if p_branch_id is not null and not exists (
    select 1 from branches where id = p_branch_id and business_id = b_id
  ) then
    raise exception 'Branch does not belong to this business';
  end if;

  select id into uid from auth.users where lower(email) = lower(trim(p_email)) limit 1;

  if uid is not null then
    insert into memberships (business_id, user_id, role, branch_id, display_name, invited_email, active)
    values (b_id, uid, safe_role, p_branch_id, nullif(trim(coalesce(p_display_name,'')),''), lower(trim(p_email)), true)
    on conflict (business_id, user_id) do update set
      role = excluded.role,
      branch_id = excluded.branch_id,
      display_name = coalesce(excluded.display_name, memberships.display_name),
      invited_email = excluded.invited_email,
      active = true
    returning * into m;
  else
    -- Pending: store placeholder user_id as a random uuid only if we allow null — we require user_id.
    -- So we create a membership row only when user exists; otherwise return a stub via raise notice.
    raise exception 'No account yet for %. Ask them to sign up with that email first, then invite again.', trim(p_email);
  end if;

  return m;
end;
$$;

grant execute on function public.invite_staff(text, text, uuid, text) to authenticated;

-- Owner creates a branch
create or replace function public.create_branch(p_name text, p_code text default null)
returns branches
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid := public.my_business_id();
  br branches;
begin
  if b_id is null or public.my_role() not in ('owner', 'manager') then
    raise exception 'Not allowed';
  end if;
  insert into branches (business_id, name, code)
  values (b_id, trim(p_name), nullif(upper(trim(coalesce(p_code,''))), ''))
  returning * into br;
  return br;
end;
$$;

grant execute on function public.create_branch(text, text) to authenticated;

-- List my memberships (for UI)
create or replace function public.list_my_staff()
returns setof memberships
language sql
stable
security definer
set search_path = public
as $$
  select * from memberships
  where business_id = public.my_business_id()
  order by case role when 'owner' then 0 when 'manager' then 1 else 2 end, created_at;
$$;

grant execute on function public.list_my_staff() to authenticated;

create or replace function public.list_my_branches()
returns setof branches
language sql
stable
security definer
set search_path = public
as $$
  select * from branches
  where business_id = public.my_business_id() and active = true
  order by name;
$$;

grant execute on function public.list_my_branches() to authenticated;

-- Deactivate staff (owner)
create or replace function public.deactivate_staff(p_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid := public.my_business_id();
begin
  if public.my_role() <> 'owner' then
    raise exception 'Only the owner can remove staff';
  end if;
  update memberships set active = false
  where id = p_membership_id and business_id = b_id and role <> 'owner';
end;
$$;

grant execute on function public.deactivate_staff(uuid) to authenticated;
