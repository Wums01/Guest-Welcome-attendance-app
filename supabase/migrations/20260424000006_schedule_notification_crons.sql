-- supabase/migrations/20260424000006_schedule_notification_crons.sql
--
-- Cron schedules for notification Edge Functions.
-- Applied via Supabase Dashboard → Edge Functions → [function] → Schedules
-- (same approach as generate-sessions per migration 20260421000002)
--
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │ Function              │ Schedule (UTC)         │ Runs at (Lagos)   │
-- ├─────────────────────────────────────────────────────────────────────┤
-- │ notify-birthdays      │ 0 21 * * *  (9 PM UTC) │ 10 PM Lagos (eve) │
-- │ notify-birthdays      │ 0 7  * * *  (7 AM UTC) │ 8 AM Lagos (morn) │
-- │ follow-up-reminders   │ 0 7  * * *  (7 AM UTC) │ 8 AM Lagos        │
-- │ evaluate-achievements │ 0 1  * * *  (1 AM UTC) │ 2 AM Lagos        │
-- └─────────────────────────────────────────────────────────────────────┘
--
-- Steps to apply in Supabase Dashboard:
-- 1. Go to Supabase Dashboard → Edge Functions
-- 2. Click notify-birthdays → Schedules tab → Add schedule
--    Cron: "0 21 * * *"  (eve notifications)
--    Body: {"mode":"eve"}
-- 3. Add second schedule for notify-birthdays
--    Cron: "0 7 * * *"   (morning notifications)
--    Body: {"mode":"morning"}
-- 4. Click follow-up-reminders → Schedules tab → Add schedule
--    Cron: "0 7 * * *"
-- 5. Click evaluate-achievements → Schedules tab → Add schedule
--    Cron: "0 1 * * *"

COMMENT ON TABLE public.device_tokens IS
  'FCM device tokens for staff. Used by Edge Functions to push birthday, '
  'anniversary, and follow-up notifications to all active staff devices.';
