-- ============================================================================
-- Post-migrate checks for 025_theme_key.sql
-- Run AFTER applying the migration. Safe / mostly read-only.
-- ============================================================================

-- 1) Column exists, type, nullability, default
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'businesses'
  and column_name = 'theme_key';
-- Expect: text, NO, 'default'::text (or similar)

-- 2) Distribution — all existing businesses should be default
select theme_key, count(*) as n
from public.businesses
group by theme_key
order by theme_key;
-- Expect: only 'default' until you deliberately change a test business

-- 3) Constraint present
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.businesses'::regclass
  and conname = 'businesses_theme_key_check';
-- Expect: CHECK (theme_key = ANY (ARRAY[...])) or equivalent IN list

-- 4) verify_receipt return shape includes theme_key
select p.proname, pg_get_function_result(p.oid) as result
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'verify_receipt';
-- Expect result text to include theme_key

-- 5) Optional: smoke-call with a known receipt (replace placeholders)
-- select * from public.verify_receipt('YOUR_RECEIPT_NO', 'YOUR_VERIFY_ID_MIN_8_CHARS');
-- Expect a row that includes theme_key = 'default' (or the business value)

-- 6) Constraint rejects invalid values (run only on a disposable test row)
-- begin;
--   update public.businesses set theme_key = 'not_a_theme' where id = 'TEST_UUID';
--   -- Expect: ERROR check constraint
-- rollback;
