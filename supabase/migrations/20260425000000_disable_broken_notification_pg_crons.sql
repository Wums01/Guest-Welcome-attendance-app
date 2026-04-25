-- supabase/migrations/20260425000000_disable_broken_notification_pg_crons.sql
--
-- Disables the notification pg_cron jobs that call Edge Functions via
-- net.http_post. These jobs have proven brittle in production because they rely
-- on a hardcoded JWT in SQL and duplicate the intended scheduling mechanism.
--
-- The supported path for these jobs is Supabase Edge Function schedules:
--   - notify-birthdays      (0 20 * * * and 0 7 * * *)
--   - follow-up-reminders   (0 7 * * *)
--   - evaluate-achievements (0 1 * * *)
--
-- See:
--   - supabase/config.toml  -> verify_jwt = false for scheduled functions
--   - 20260424000006_schedule_notification_crons.sql for the desired schedules

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('notify-birthdays-eve');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    BEGIN
      PERFORM cron.unschedule('notify-birthdays-morning');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    BEGIN
      PERFORM cron.unschedule('follow-up-reminders');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    BEGIN
      PERFORM cron.unschedule('evaluate-achievements');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
END $$;
