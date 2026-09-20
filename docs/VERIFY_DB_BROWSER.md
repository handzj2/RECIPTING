# Browser checks (while signed in on app.html)

Open **app.html** signed in → DevTools → Console.

```js
// Requires supabase client already on page as `sb`
async function auditDbQuick() {
  const out = {};
  // 1) Try forbidden UPDATE
  const { data: rows, error: uerr } = await sb.from("receipts")
    .update({ amount: 1 })
    .eq("status", "VALID")
    .select("receipt_no")
    .limit(1);
  out.update_attempt = { rows: rows, error: uerr && uerr.message };
  // Expect: rows null/[] and/or error about policy / 0 rows

  // 2) Role
  const role = await sb.rpc("my_role");
  out.my_role = role;

  // 3) Can void?
  const cv = await sb.rpc("can_void");
  out.can_void = cv;

  // 4) Branches visible
  const br = await sb.rpc("list_my_branches");
  out.branches = br;

  console.table(out);
  return out;
}
auditDbQuick();
```

| Role | `my_role` | `can_void` | UPDATE attempt |
|------|-----------|------------|----------------|
| Owner | owner | true | 0 rows / denied |
| Manager | manager | true | 0 rows / denied |
| Cashier | cashier | false | 0 rows / denied |

Cashier: also run `void_receipt` on a real number → expect error *Only the owner or a manager…*
