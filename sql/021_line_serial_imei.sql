-- ============================================================================
-- HandzJ Digital Receipts — Migration 021
-- Document optional serial / IMEI on receipt line items
--
-- Storage: already in receipts.lines jsonb (007).
-- Shape per line:
--   { name, qty, price, total, serial?, imei? }
--
-- serial / imei are optional. Typical for phone shops, laptops, electronics.
-- No schema change required beyond comment — app reads/writes these keys.
-- ============================================================================

comment on column public.receipts.lines is
  'JSON array of line items: [{name, qty, price, total, serial?, imei?}, ...]. serial and imei optional for devices.';

-- Optional dedicated columns for single-item search (nullable; multi-line still uses lines jsonb)
alter table public.receipts add column if not exists primary_serial text;
alter table public.receipts add column if not exists primary_imei text;

create index if not exists receipts_primary_serial_idx
  on public.receipts (business_id, primary_serial)
  where primary_serial is not null;

create index if not exists receipts_primary_imei_idx
  on public.receipts (business_id, primary_imei)
  where primary_imei is not null;

comment on column public.receipts.primary_serial is
  'Optional denormalised first serial from lines — for search; source of truth remains lines jsonb';
comment on column public.receipts.primary_imei is
  'Optional denormalised first IMEI from lines — for search; source of truth remains lines jsonb';
