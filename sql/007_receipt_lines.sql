-- Store multiple line items on each receipt (JSON array)
alter table receipts add column if not exists lines jsonb;

comment on column receipts.lines is '[{name, qty, price, total}, ...]';
