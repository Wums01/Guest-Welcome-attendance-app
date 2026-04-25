-- supabase/migrations/20260425000001_reschedule_notification_pg_crons_without_jwt.sql
--
-- Re-creates recurring notification cron jobs using unauthenticated HTTP calls
-- to Edge Functions. This works with the function config in supabase/config.toml:
--   verify_jwt = false
--
-- This removes the brittle dependency on a hardcoded bearer token in SQL while
-- preserving fully automatic recurring schedules in the Cron integration.

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

    PERFORM cron.schedule(
      'notify-birthdays-eve',
      '0 20 * * *',
      $cron$
      select net.http_post(
        url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/notify-birthdays',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:='{"mode":"eve"}'::jsonb
      ) as request_id
      $cron$
    );

    PERFORM cron.schedule(
      'notify-birthdays-morning',
      '0 7 * * *',
      $cron$
      select net.http_post(
        url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/notify-birthdays',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:='{"mode":"morning"}'::jsonb
      ) as request_id
      $cron$
    );

    PERFORM cron.schedule(
      'follow-up-reminders',
      '0 7 * * *',
      $cron$
      select net.http_post(
        url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/follow-up-reminders',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:='{}'::jsonb
      ) as request_id
      $cron$
    );

    PERFORM cron.schedule(
      'evaluate-achievements',
      '0 1 * * *',
      $cron$
      select net.http_post(
        url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/evaluate-achievements',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:='{}'::jsonb
      ) as request_id
      $cron$
    );
  END IF;
END $$;
