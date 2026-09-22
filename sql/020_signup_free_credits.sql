-- ============================================================================
-- HandzJ Digital Receipts — Migration 020
-- Grant 5 free receipt credits automatically on signup
--
-- Requires 014 (grant_free_starter_credits, FREE_5 catalog) and preferably 019.
-- Safe to run more than once.
-- ============================================================================

create or replace function public.signup_business(
  p_name text,
  p_tagline text default null,
  p_phone text default null,
  p_whatsapp text default null,
  p_email text default null,
  p_prefix text default null
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare
  existing businesses;
  created businesses;
  safe_prefix text;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  select * into existing from businesses where owner_id = auth.uid() limit 1;
  if found then
    -- Idempotent: still ensure free credits exist for older signups that missed them
    begin
      perform public.grant_free_starter_credits(existing.id);
    exception when others then
      null; -- catalog/migration not present yet; do not block login
    end;
    return existing;
  end if;

  if p_name is null or length(trim(p_name)) < 2 then
    raise exception 'Business name is required';
  end if;

  safe_prefix := upper(regexp_replace(coalesce(nullif(trim(p_prefix),''), p_name), '[^A-Za-z]', '', 'g'));
  safe_prefix := left(coalesce(nullif(safe_prefix,''), 'BIZ'), 4);

  insert into businesses (owner_id, name, tagline, phone, whatsapp, email, prefix,
                          plan, subscription_status, trial_ends_at)
  values (auth.uid(), trim(p_name), nullif(trim(coalesce(p_tagline,'')),''),
          nullif(trim(coalesce(p_phone,'')),''), nullif(trim(coalesce(p_whatsapp,'')),''),
          coalesce(nullif(trim(coalesce(p_email,'')),''), auth.email()),
          safe_prefix, 'trial', 'trialing',
          now() + interval '5 days')
  returning * into created;

  -- 5 free receipt credits (once per business; grant_free_starter_credits is idempotent)
  begin
    perform public.grant_free_starter_credits(created.id);
  exception when others then
    -- Do not fail signup if pack catalog is not migrated yet
    null;
  end;

  return created;
end;
$$;

grant execute on function public.signup_business(text,text,text,text,text,text) to authenticated;

-- Optional: backfill free credits for existing businesses that never received FREE_5
do $$
declare
  r record;
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'receipt_pack_purchases'
  ) then
    return;
  end if;

  for r in
    select b.id
      from businesses b
     where not exists (
       select 1 from receipt_pack_purchases p
        where p.business_id = b.id and p.pack_code = 'FREE_5'
     )
  loop
    begin
      perform public.grant_free_starter_credits(r.id);
    exception when others then
      null;
    end;
  end loop;
end $$;
