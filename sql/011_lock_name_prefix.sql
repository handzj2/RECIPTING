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
