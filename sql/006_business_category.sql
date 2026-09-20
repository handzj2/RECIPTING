-- Optional: store business type for auto form labels (goods / service / software)
alter table businesses add column if not exists category text default 'retail';

comment on column businesses.category is 'retail|boutique|electronics|phones|grocery|service|software|other';
