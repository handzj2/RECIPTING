-- ============================================================================
-- HandzJ Digital Receipts — Migration 016
-- Usage-based credit limits (enforcement layer)
--
-- Requires 014 + 015. Safe to run more than once.
--
-- Rules enforced:
--   1. Active paid subscription  → unlimited issuance (no credit consumed)
--   2. Active free trial         → issuance allowed (no credit consumed)
--   3. Pack credits remaining >0 → issuance allowed; 1 credit consumed on success
--   4. Otherwise                 → issuance blocked with clear error
--   5. View / download / share / verify / void → never consume a credit
--   6. Suspended / terminated accounts → always blocked
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Canonical business_active (trial OR subscription OR credits)
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
        -- Paid subscription still valid
        (b.subscription_status = 'active'
          and (b.subscribed_until is null or b.subscribed_until > now()))
        -- Or free trial still running
        or (coalesce(b.subscription_status, 'trialing') = 'trialing'
          and b.trial_ends_at is not null
          and b.trial_ends_at > now())
        -- Or pack credits remaining
        or public.receipt_credits_remaining(b_id) > 0
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. Why is this business allowed (or not)? — for UI + debugging
-- ---------------------------------------------------------------------------
create or replace function public.issuance_status(b_id uuid default null)
returns table (
  allowed              boolean,
  mode                 text,          -- 'subscription' | 'trial' | 'credits' | 'blocked'
  credits_remaining    int,
  subscription_status  text,
  trial_ends_at        timestamptz,
  subscribed_until     timestamptz,
  account_status       text,
  message              text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  bid uuid := coalesce(b_id, public.my_business_id());
  b   businesses%rowtype;
  cred int;
  sub_ok boolean;
  trial_ok boolean;
begin
  if bid is null then
    allowed := false;
    mode := 'blocked';
    credits_remaining := 0;
    message := 'No business linked to this account.';
    return next;
    return;
  end if;

  select * into b from businesses where id = bid;
  if not found then
    allowed := false;
    mode := 'blocked';
    credits_remaining := 0;
    message := 'Business not found.';
    return next;
    return;
  end if;

  cred := public.receipt_credits_remaining(bid);
  sub_ok := (b.subscription_status = 'active'
             and (b.subscribed_until is null or b.subscribed_until > now()));
  trial_ok := (coalesce(b.subscription_status, 'trialing') = 'trialing'
               and b.trial_ends_at is not null
               and b.trial_ends_at > now());

  subscription_status := b.subscription_status;
  trial_ends_at := b.trial_ends_at;
  subscribed_until := b.subscribed_until;
  account_status := coalesce(b.account_status, 'active');
  credits_remaining := cred;

  if coalesce(b.account_status, 'active') in ('suspended', 'terminated') then
    allowed := false;
    mode := 'blocked';
    message := 'Account is ' || b.account_status || '. Contact support.';
    return next;
    return;
  end if;

  if sub_ok then
    allowed := true;
    mode := 'subscription';
    message := 'Subscription active — unlimited issuance.';
    return next;
    return;
  end if;

  if trial_ok then
    allowed := true;
    mode := 'trial';
    message := 'Free trial active.';
    return next;
    return;
  end if;

  if cred > 0 then
    allowed := true;
    mode := 'credits';
    message := cred::text || ' receipt credit' || case when cred = 1 then '' else 's' end || ' remaining.';
    return next;
    return;
  end if;

  allowed := false;
  mode := 'blocked';
  message := 'No credits remaining. Buy a receipt pack or subscribe to keep issuing.';
  return next;
end;
$$;

grant execute on function public.issuance_status(uuid) to authenticated;

-- Merchant convenience (own business only)
create or replace function public.my_issuance_status()
returns table (
  allowed              boolean,
  mode                 text,
  credits_remaining    int,
  subscription_status  text,
  trial_ends_at        timestamptz,
  subscribed_until     timestamptz,
  account_status       text,
  message              text
)
language sql
stable
security definer
set search_path = public
as $$
  select * from public.issuance_status(public.my_business_id());
$$;

grant execute on function public.my_issuance_status() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. next_receipt_no — refuse with explicit reason before allocating a number
-- ---------------------------------------------------------------------------
create or replace function public.next_receipt_no()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid;
  b_prefix text;
  yr int := extract(year from now())::int;
  n int;
  candidate text;
  guard int := 0;
  st record;
begin
  b_id := public.my_business_id();
  if b_id is null then
    raise exception 'No business for this account';
  end if;

  select * into st from public.issuance_status(b_id) limit 1;

  if not st.allowed then
    if st.mode = 'blocked' and coalesce(st.account_status, 'active') in ('suspended', 'terminated') then
      raise exception 'ACCOUNT_BLOCKED: %', st.message;
    end if;
    if st.credits_remaining is not null and st.credits_remaining < 1
       and coalesce(st.subscription_status, '') is distinct from 'active' then
      raise exception 'NO_CREDITS: %', st.message;
    end if;
    raise exception 'TRIAL_EXPIRED: %', st.message;
  end if;

  select coalesce(prefix, 'BIZ') into b_prefix from businesses where id = b_id;

  insert into receipt_sequences (business_id, year, seq)
  values (b_id, yr, 1)
  on conflict (business_id, year) do update set seq = receipt_sequences.seq + 1
  returning seq into n;

  loop
    candidate := b_prefix || '-' || yr || '-' || lpad(n::text, 6, '0');
    exit when not exists (
      select 1 from receipts where business_id = b_id and receipt_no = candidate
    );
    guard := guard + 1;
    if guard > 200 then
      raise exception 'Could not allocate a receipt number';
    end if;
    update receipt_sequences set seq = seq + 1
      where business_id = b_id and year = yr returning seq into n;
  end loop;

  return candidate;
end;
$$;

grant execute on function public.next_receipt_no() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Consumption trigger — only when not on subscription; fail closed
-- ---------------------------------------------------------------------------
create or replace function public.consume_receipt_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bal int;
  has_sub boolean;
  trial_ok boolean;
  acct text;
begin
  if NEW.status is distinct from 'VALID' then
    return NEW;
  end if;

  select coalesce(account_status, 'active'),
         (subscription_status = 'active'
            and (subscribed_until is null or subscribed_until > now())),
         (coalesce(subscription_status, 'trialing') = 'trialing'
            and trial_ends_at is not null
            and trial_ends_at > now())
    into acct, has_sub, trial_ok
    from businesses where id = NEW.business_id;

  if acct in ('suspended', 'terminated') then
    raise exception 'ACCOUNT_BLOCKED: account is %', acct;
  end if;

  -- Subscription or active trial: no credit consumed
  if has_sub or trial_ok then
    return NEW;
  end if;

  -- Pack path: require and consume 1 credit
  bal := public.receipt_credits_remaining(NEW.business_id);

  if bal < 1 then
    raise exception 'NO_CREDITS: you have no receipt credits remaining — buy a pack or subscribe';
  end if;

  insert into receipt_credit_ledger (
    business_id, receipt_id, entry_type, credits_delta, balance_after, note, created_by
  ) values (
    NEW.business_id, NEW.id, 'consumption', -1, bal - 1,
    'Receipt issued: ' || NEW.receipt_no, auth.uid()
  );

  return NEW;
end;
$$;

drop trigger if exists trg_consume_receipt_credit on public.receipts;
create trigger trg_consume_receipt_credit
  after insert on public.receipts
  for each row
  execute function public.consume_receipt_credit();

-- ---------------------------------------------------------------------------
-- 5. BEFORE INSERT guard (defense in depth — catches direct inserts)
-- ---------------------------------------------------------------------------
create or replace function public.receipts_require_issuance_right()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  st record;
begin
  select * into st from public.issuance_status(NEW.business_id) limit 1;
  if not st.allowed then
    if coalesce(st.account_status, 'active') in ('suspended', 'terminated') then
      raise exception 'ACCOUNT_BLOCKED: %', st.message;
    end if;
    if st.mode = 'blocked' and (st.credits_remaining is null or st.credits_remaining < 1) then
      raise exception 'NO_CREDITS: %', st.message;
    end if;
    raise exception 'TRIAL_EXPIRED: %', st.message;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_receipts_require_issuance_right on public.receipts;
create trigger trg_receipts_require_issuance_right
  before insert on public.receipts
  for each row
  execute function public.receipts_require_issuance_right();

-- ---------------------------------------------------------------------------
-- 6. Extend my_credit_summary (014 had fewer OUT columns — must DROP first)
-- ---------------------------------------------------------------------------
drop function if exists public.my_credit_summary();

create function public.my_credit_summary()
returns table (
  credits_remaining        int,
  total_purchased          int,
  total_consumed           int,
  has_active_subscription  boolean,
  subscription_status      text,
  trial_ends_at            timestamptz,
  subscribed_until         timestamptz,
  issuance_mode            text,
  issuance_allowed         boolean,
  issuance_message         text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    public.my_receipt_credits(),
    coalesce((select sum(credits_delta)::int from receipt_credit_ledger
               where business_id = public.my_business_id()
                 and entry_type = 'purchase'), 0),
    coalesce((select sum(-credits_delta)::int from receipt_credit_ledger
               where business_id = public.my_business_id()
                 and entry_type = 'consumption'), 0),
    exists (
      select 1 from businesses b
       where b.id = public.my_business_id()
         and b.subscription_status = 'active'
         and (b.subscribed_until is null or b.subscribed_until > now())
    ),
    (select subscription_status from businesses where id = public.my_business_id()),
    (select trial_ends_at from businesses where id = public.my_business_id()),
    (select subscribed_until from businesses where id = public.my_business_id()),
    (select mode from public.issuance_status(public.my_business_id()) limit 1),
    (select allowed from public.issuance_status(public.my_business_id()) limit 1),
    (select message from public.issuance_status(public.my_business_id()) limit 1);
$$;

grant execute on function public.my_credit_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- Done. Issuance is now usage-based:
--   • Subscription / trial → free issuance
--   • Pack credits → 1 credit per successful issue
--   • Zero credits + no trial/sub → blocked (NO_CREDITS)
-- ============================================================================
