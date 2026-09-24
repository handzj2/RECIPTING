-- HandzJ: audit image-related data in Supabase
-- Marketing images live in the static deploy (Vercel public/), NOT in SQL.
-- This script only helps with business logos / storage if you use them.

-- 1) Businesses with logo_url set
SELECT id, name, logo_url,
       CASE
         WHEN logo_url IS NULL OR logo_url = '' THEN 'empty'
         WHEN logo_url LIKE 'data:%' THEN 'data-url (in DB row)'
         WHEN logo_url LIKE 'http%' THEN 'external-url'
         ELSE 'other'
       END AS logo_kind
FROM businesses
ORDER BY created_at DESC NULLS LAST;

-- 2) Count logo usage
SELECT
  count(*) FILTER (WHERE logo_url IS NULL OR logo_url = '') AS no_logo,
  count(*) FILTER (WHERE logo_url LIKE 'data:%') AS data_url_logos,
  count(*) FILTER (WHERE logo_url LIKE 'http%') AS http_logos,
  count(*) AS total_businesses
FROM businesses;

-- 3) If you created a Storage bucket for logos, list via Dashboard:
--    Storage → buckets → objects
-- Do NOT delete logo objects that still match businesses.logo_url.

-- 4) Marketing JPGs/WebPs are NOT in Postgres.
--    Remove them from the repo + redeploy Vercel (see scripts/cleanup-unused-marketing-images.sh).
