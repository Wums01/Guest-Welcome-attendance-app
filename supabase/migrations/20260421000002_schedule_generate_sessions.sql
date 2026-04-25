-- =============================================================================
-- Schedule Edge Function via Supabase Management API (Applied after deployment)
-- =============================================================================
-- NOTE: This migration documents the Edge Function scheduling.
-- The actual cron schedule is set via Supabase Management API or Dashboard.
--
-- Edge Function Details:
--   Name: generate-sessions
--   Location: supabase/functions/generate-sessions/index.ts
--   Schedule: 0 23 * * *  (daily at 23:00 UTC = 00:00 Africa/Lagos)
--
-- To verify the schedule is active:
--   1. Check Supabase Dashboard → Functions → generate-sessions → Schedules
--   2. Or run: curl -X POST https://xfornseashjnezqqjeun.supabase.co/functions/v1/generate-sessions \
--        -H 'Authorization: Bearer [ANON_KEY]'
--

COMMENT ON FUNCTION public.auto_generate_weekly_sessions IS
  'Called daily by Edge Function at 23:00 UTC (00:00 Africa/Lagos). Creates 3 sessions on Sundays or 1 session on Wednesdays for active programs. Fully idempotent: safe to call multiple times without duplicates.';
