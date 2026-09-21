-- Run after 013 to inspect policies
select schemaname, tablename, policyname, roles, cmd, qual is not null as has_using, with_check is not null as has_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

select c.relname as table,
       c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in (
    'businesses','receipts','receipt_sequences','receipt_events',
    'branches','memberships','platform_admins','platform_events'
  )
order by 1;
