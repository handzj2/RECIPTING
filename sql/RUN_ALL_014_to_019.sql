-- ============================================================================
-- HandzJ Digital Receipts — Run pack/subscription commercial layer
-- Run AFTER 002–013 (or RUN_ALL_010_to_013.sql) are applied.
-- Paste into Supabase SQL Editor and Run.
-- ============================================================================

\i 014_receipt_packs_ledger.sql
-- Note: Supabase SQL Editor does not support \i — paste each file in order instead:
--   1. 014_receipt_packs_ledger.sql
--   2. 015_admin_pack_control.sql
--   3. 016_usage_based_credit_limits.sql
--   4. 017_credit_usage_audit.sql
--   5. 018_subscription_billing_audit.sql
--   6. 019_hardening.sql

-- This file is a checklist marker. Prefer running the six files above in order.
select 'Run 014 → 015 → 016 → 017 → 018 → 019 individually in Supabase SQL Editor' as instruction;
