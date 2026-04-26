-- supabase/migrations/20260424000008_setup_cron_schedules.sql
--
-- Sets up pg_cron schedules that call notification Edge Functions daily.
-- Times are in UTC (Lagos is UTC+1):
--   0 20 * * *  = 9 PM Lagos  (birthday eve alerts)
--   0 7  * * *  = 8 AM Lagos  (birthday morning + follow-up reminders)
--   0 1  * * *  = 2 AM Lagos  (nightly achievement evaluation)

-- Remove any existing schedules with these names (safe to re-run)
select cron.unschedule('notify-birthdays-eve')     where exists (select 1 from cron.job where jobname = 'notify-birthdays-eve');
select cron.unschedule('notify-birthdays-morning') where exists (select 1 from cron.job where jobname = 'notify-birthdays-morning');
select cron.unschedule('follow-up-reminders')      where exists (select 1 from cron.job where jobname = 'follow-up-reminders');
select cron.unschedule('evaluate-achievements')    where exists (select 1 from cron.job where jobname = 'evaluate-achievements');

-- Birthday eve notification (9 PM Lagos)
select cron.schedule(
  'notify-birthdays-eve',
  '0 20 * * *',
  $$select net.http_post(
      url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/notify-birthdays',
      headers:='{"Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhmb3Juc2Vhc2hqbmV6cXFqZXVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMjEyNjksImV4cCI6MjA4ODc5NzI2OX0.vL_4I6V4WDxnu1IhPUNB4J8idwr9c4LbpNs0hMSJAQo","Content-Type":"application/json"}'::jsonb,
      body:='{"mode":"eve"}'::jsonb
  ) as request_id$$
);

-- Birthday morning notification (8 AM Lagos)
select cron.schedule(
  'notify-birthdays-morning',
  '0 7 * * *',
  $$select net.http_post(
      url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/notify-birthdays',
      headers:='{"Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhmb3Juc2Vhc2hqbmV6cXFqZXVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMjEyNjksImV4cCI6MjA4ODc5NzI2OX0.vL_4I6V4WDxnu1IhPUNB4J8idwr9c4LbpNs0hMSJAQo","Content-Type":"application/json"}'::jsonb,
      body:='{"mode":"morning"}'::jsonb
  ) as request_id$$
);

-- Follow-up reminders (8 AM Lagos)
select cron.schedule(
  'follow-up-reminders',
  '0 7 * * *',
  $$select net.http_post(
      url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/follow-up-reminders',
      headers:='{"Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhmb3Juc2Vhc2hqbmV6cXFqZXVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMjEyNjksImV4cCI6MjA4ODc5NzI2OX0.vL_4I6V4WDxnu1IhPUNB4J8idwr9c4LbpNs0hMSJAQo","Content-Type":"application/json"}'::jsonb,
      body:='{}'::jsonb
  ) as request_id$$
);

-- Nightly achievement evaluation (2 AM Lagos)
select cron.schedule(
  'evaluate-achievements',
  '0 1 * * *',
  $$select net.http_post(
      url:='https://xfornseashjnezqqjeun.supabase.co/functions/v1/evaluate-achievements',
      headers:='{"Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhmb3Juc2Vhc2hqbmV6cXFqZXVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMjEyNjksImV4cCI6MjA4ODc5NzI2OX0.vL_4I6V4WDxnu1IhPUNB4J8idwr9c4LbpNs0hMSJAQo","Content-Type":"application/json"}'::jsonb,
      body:='{}'::jsonb
  ) as request_id$$
);
