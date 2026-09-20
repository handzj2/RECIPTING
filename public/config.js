/* HandzJ Digital Receipts — cloud config
   Public values only. The anon key is safe to ship: the database is protected
   by Supabase Auth + row level security (see sql/002_auth_multitenant.sql).
   Hard-refresh after editing (Ctrl+F5).
*/
window.HANDZJ_CONFIG = {
  SUPABASE_URL: "https://lqvszhaosztrlxteclft.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxxdnN6aGFvc3p0cmx4dGVjbGZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk3Mzc2MDcsImV4cCI6MjEwNTMxMzYwN30.C0eMySpJvTP59MNoHPGdFxrHSshqAgnJnPqRRn7s-ic",

  /* Shown to a tenant whose trial has ended, so they know who to pay. */
  SUPPORT_CONTACT: "0781 909 507 / handzj2@gmail.com",

  APP_URL: "",

  /* Optional SMS gateway. Leave empty = SMS button hidden (no fake send).
     When set, POST JSON { to, message, receipt_no } to this URL from the browser.
     You must implement the server/provider yourself. */
  SMS_ENDPOINT: ""
};
