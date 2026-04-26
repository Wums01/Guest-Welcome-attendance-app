-- =============================================================================
-- Fix pg_cron schedule + add verify helper
-- =============================================================================
-- WHY THIS MIGRATION EXISTS:
--   Migration 20260317000000 contained invalid PostgreSQL syntax for the cron
--   unschedule call:
--
--     SELECT cron.unschedule('job') WHERE EXISTS (...);   ← INVALID
--
--   PostgreSQL does not allow a WHERE clause on a bare SELECT returning a
--   scalar function.  This caused the entire cron.schedule() call to be
--   skipped silently, leaving NO cron job scheduled in production.
--
-- THIS MIGRATION:
--   1. Safely removes the broken/missing job using a DO block with EXCEPTION
--   2. Re-schedules correctly using PERFORM inside a DO block
--   3. Adds public.verify_session_generation() for monitoring / test calls
-- =============================================================================

-- ── Step 1: Remove old job safely ─────────────────────────────────────────────

DO $$
BEGIN
  -- Only attempt if pg_cron extension is present
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('auto-generate-weekly-sessions');
    EXCEPTION WHEN OTHERS THEN
      -- Job didn't exist yet — that's fine
      NULL;
    END;
  END IF;
END;
$$;

-- ── Step 2: Re-schedule with correct syntax ───────────────────────────────────
-- 23:00 UTC daily  =  00:00 Africa/Lagos (UTC+1, Nigeria has no DST)
-- The SQL function itself checks whether today is Sunday (DOW=0) or
-- Wednesday (DOW=3) in Lagos time, so running it daily is safe and cheap.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'auto-generate-weekly-sessions',
      '0 23 * * *',
      'SELECT public.auto_generate_weekly_sessions();'
    );
    RAISE NOTICE 'pg_cron job "auto-generate-weekly-sessions" scheduled at 23:00 UTC.';
  ELSE
    RAISE NOTICE 'pg_cron extension not available on this plan. '
                 'Use the Edge Function (generate-sessions) instead.';
  END IF;
END;
$$;

-- ── Step 3: Verify helper ─────────────────────────────────────────────────────
-- Returns a snapshot of what will happen when the generation runs.
-- Call via: SELECT * FROM public.verify_session_generation();
-- Useful in tests, dashboards, and manual checks.

CREATE OR REPLACE FUNCTION public.verify_session_generation()
RETURNS TABLE (
  check_name        TEXT,
  status            TEXT,
  detail            TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_lagos_today     DATE := (NOW() AT TIME ZONE 'Africa/Lagos')::DATE;
  v_lagos_weekday   INT  := EXTRACT(DOW FROM v_lagos_today)::INT;
  v_day_name        TEXT;
  v_sunday_count    INT;
  v_wednesday_count INT;
  v_cron_scheduled  BOOL := FALSE;
  v_existing_today  INT;
BEGIN
  -- Lagos day name
  v_day_name := TO_CHAR(v_lagos_today, 'Day');

  -- 1. Current Lagos date
  RETURN QUERY SELECT
    'lagos_date'::TEXT,
    v_lagos_today::TEXT,
    ('Weekday DOW=' || v_lagos_weekday || ' (' || TRIM(v_day_name) || ')')::TEXT;

  -- 2. Is today a service day?
  RETURN QUERY SELECT
    'is_service_day'::TEXT,
    CASE WHEN v_lagos_weekday IN (0, 3) THEN 'YES' ELSE 'NO' END,
    CASE v_lagos_weekday
      WHEN 0 THEN 'Sunday — 3 services will be created'
      WHEN 3 THEN 'Wednesday — 1 Switch Service will be created'
      ELSE 'Not a service day — function returns 0 sessions'
    END;

  -- 3. Active Sunday programs
  SELECT COUNT(*) INTO v_sunday_count
  FROM public.programs
  WHERE program_type = 'sunday'
    AND is_tbd = FALSE
    AND start_date <= v_lagos_today
    AND (end_date IS NULL OR end_date >= v_lagos_today);

  RETURN QUERY SELECT
    'active_sunday_programs'::TEXT,
    v_sunday_count::TEXT,
    CASE WHEN v_sunday_count > 0
      THEN 'Will generate ' || (v_sunday_count * 3) || ' sessions on next Sunday'
      ELSE 'No active Sunday programs found'
    END;

  -- 4. Active Wednesday programs
  SELECT COUNT(*) INTO v_wednesday_count
  FROM public.programs
  WHERE program_type = 'wednesday'
    AND is_tbd = FALSE
    AND start_date <= v_lagos_today
    AND (end_date IS NULL OR end_date >= v_lagos_today);

  RETURN QUERY SELECT
    'active_wednesday_programs'::TEXT,
    v_wednesday_count::TEXT,
    CASE WHEN v_wednesday_count > 0
      THEN 'Will generate ' || v_wednesday_count || ' session(s) on next Wednesday'
      ELSE 'No active Wednesday programs found'
    END;

  -- 5. Sessions already generated today
  SELECT COUNT(*) INTO v_existing_today
  FROM public.sessions
  WHERE date = v_lagos_today;

  RETURN QUERY SELECT
    'sessions_today'::TEXT,
    v_existing_today::TEXT,
    CASE WHEN v_existing_today > 0
      THEN 'Sessions already exist for today — generation will be skipped (idempotent)'
      ELSE 'No sessions for today yet'
    END;

  -- 6. pg_cron job status
  BEGIN
    SELECT TRUE INTO v_cron_scheduled
    FROM cron.job
    WHERE jobname = 'auto-generate-weekly-sessions';
  EXCEPTION WHEN OTHERS THEN
    v_cron_scheduled := FALSE;
  END;

  RETURN QUERY SELECT
    'cron_job_scheduled'::TEXT,
    CASE WHEN v_cron_scheduled THEN 'YES' ELSE 'NO (use Edge Function)' END,
    CASE WHEN v_cron_scheduled
      THEN 'pg_cron will fire at 23:00 UTC (00:00 Lagos) every night'
      ELSE 'pg_cron not available — deploy the generate-sessions Edge Function and schedule it'
    END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_session_generation() TO authenticated;
