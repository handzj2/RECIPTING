# Staff, branches & fraud isolation

## Run SQL first

In Supabase → SQL Editor, run:

`sql/008_staff_branches_roles.sql`

## Roles

| Role | Issue / print | Void | Settings | Invite staff | Branches |
|------|---------------|------|----------|--------------|----------|
| Owner | Yes | Yes | Yes | Yes | Yes |
| Manager | Yes | Yes | Limited | No | Create |
| Cashier | Yes | No | No | No | Own branch only |

## How to add a worker

1. Worker signs up at `/login.html` with **their own email** (or owner creates them as a normal user first).
2. Owner opens **Settings → Team & branches → Invite staff**.
3. Enter worker email, role (cashier/manager), optional branch.
4. Worker signs in → sees **that business only** (RLS + membership).

## Branches

Owner/manager: **Create branch** in Settings.  
Assign cashiers to a branch when inviting.  
Receipts store `branch_id` + `issued_by` / `issued_by_name`.

## Fraud controls

- One login ≠ shared password: each person has their own account.
- `business_id` isolation: another shop with the same name cannot see your receipts.
- Receipt numbers unique per business; void does not re-issue the same number as VALID.
- Void only owner/manager; reason required.
- Public verify needs receipt no + verify id; shows VOIDED when voided.
- Issued-by is stamped on every new receipt.

## Same company name

Allowed. Identity is **auth user + membership + business_id**, not the display name.
