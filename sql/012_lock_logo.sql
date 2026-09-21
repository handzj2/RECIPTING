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
