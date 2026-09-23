-- ============================================================================
-- Migration 026 — Controlled RPC to set businesses.theme_key
-- Owner or manager only. Single field. No arbitrary CSS.
-- Safe to re-run.
-- ============================================================================

create or replace function public.set_business_theme_key(p_theme_key text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  b_id uuid := public.my_business_id();
  role text := public.my_role();
  next_key text;
begin
  if b_id is null then
    raise exception 'Not a member of any business';
  end if;

  if coalesce(role, '') not in ('owner', 'manager') then
    raise exception 'Only the tenant admin or a manager can change verification appearance';
  end if;

  next_key := lower(trim(coalesce(p_theme_key, '')));
  if next_key not in ('default', 'forest', 'navy_gold', 'teal_slate') then
    raise exception 'Invalid theme_key. Allowed: default, forest, navy_gold, teal_slate';
  end if;

  update public.businesses
     set theme_key = next_key
   where id = b_id;

  return next_key;
end;
$$;

revoke all on function public.set_business_theme_key(text) from public;
grant execute on function public.set_business_theme_key(text) to authenticated;

comment on function public.set_business_theme_key(text) is
  'Owner/manager only. Sets businesses.theme_key for the caller''s tenant to one of: default, forest, navy_gold, teal_slate. Public verification only.';
