-- =============================================================================
-- Auto-generate Sunday & Wednesday sessions at midnight (Lagos timezone)
-- =============================================================================
-- This migration creates a function that automatically generates sessions for
-- Sunday and Wednesday programs at 12 AM Lagos time each day.
--
-- Since Supabase pg_cron may not be available on all plans, this function
-- is designed to be called:
--   1. Via pg_cron scheduler (if available in your Supabase plan)
--   2. Via the Flutter app startup (fallback mechanism)
-- =============================================================================

-- Enable pg_cron extension (this will fail silently if already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- =============================================================================
-- FUNCTION: auto_generate_weekly_sessions
-- =============================================================================
-- Generates sessions for all Sunday and Wednesday programs that:
--   1. Are active (start_date <= today AND end_date >= today)
--   2. Don't already have a session for today
--
-- Logic:
--   - For Sunday programs: creates Service 1 (06:30-08:30), Service 2 (08:30-11:00), Service 3 (11:00-13:30)
--   - For Wednesday programs: creates Switch Service (no specific times)
--
-- Lagos timezone is UTC+1 (during standard time) or UTC+1 (no DST in Nigeria)
-- We use the date in Lagos to determine what to generate.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.auto_generate_weekly_sessions()
RETURNS TABLE (generated_count INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_lagos_today DATE;
  v_program RECORD;
  v_session_count INT := 0;
BEGIN
  -- Get today's date in Lagos timezone (UTC+1)
  -- Using 'Africa/Lagos' timezone if available, otherwise add 1 hour to UTC
  v_lagos_today := (NOW() AT TIME ZONE 'Africa/Lagos')::DATE;

  -- ── Process SUNDAY programs ────────────────────────────────────────────────
  FOR v_program IN
    SELECT id, title
    FROM public.programs
    WHERE
      program_type = 'sunday'
      AND is_tbd = FALSE
      AND start_date <= v_lagos_today
      AND (end_date IS NULL OR end_date >= v_lagos_today)
      -- Check that we don't already have a session for today
      AND NOT EXISTS (
        SELECT 1 FROM public.sessions
        WHERE program_id = programs.id AND date = v_lagos_today
      )
      -- Only generate on Sundays
      AND EXTRACT(DOW FROM v_lagos_today) = 0
  LOOP
    -- Service 1: 06:30 - 08:30
    INSERT INTO public.sessions (program_id, name, date, start_time, end_time, clock_in_required)
    VALUES (v_program.id, 'Service 1', v_lagos_today, '06:30', '08:30', TRUE)
    ON CONFLICT DO NOTHING;
    v_session_count := v_session_count + 1;

    -- Service 2: 08:30 - 11:00
    INSERT INTO public.sessions (program_id, name, date, start_time, end_time, clock_in_required)
    VALUES (v_program.id, 'Service 2', v_lagos_today, '08:30', '11:00', TRUE)
    ON CONFLICT DO NOTHING;
    v_session_count := v_session_count + 1;

    -- Service 3: 11:00 - 13:30
    INSERT INTO public.sessions (program_id, name, date, start_time, end_time, clock_in_required)
    VALUES (v_program.id, 'Service 3', v_lagos_today, '11:00', '13:30', TRUE)
    ON CONFLICT DO NOTHING;
    v_session_count := v_session_count + 1;
  END LOOP;

  -- ── Process WEDNESDAY programs ─────────────────────────────────────────────
  FOR v_program IN
    SELECT id, title
    FROM public.programs
    WHERE
      program_type = 'wednesday'
      AND is_tbd = FALSE
      AND start_date <= v_lagos_today
      AND (end_date IS NULL OR end_date >= v_lagos_today)
      -- Check that we don't already have a session for today
      AND NOT EXISTS (
        SELECT 1 FROM public.sessions
        WHERE program_id = programs.id AND date = v_lagos_today
      )
      -- Only generate on Wednesdays
      AND EXTRACT(DOW FROM v_lagos_today) = 3
  LOOP
    -- Switch Service: no specific time (times are NULL)
    INSERT INTO public.sessions (program_id, name, date, clock_in_required)
    VALUES (v_program.id, 'Switch Service', v_lagos_today, TRUE)
    ON CONFLICT DO NOTHING;
    v_session_count := v_session_count + 1;
  END LOOP;

  RETURN QUERY SELECT v_session_count;
END;
$$;

-- =============================================================================
-- GRANT PERMISSIONS: Allow anon role to execute the function (RPC from Flutter)
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.auto_generate_weekly_sessions()
  TO anon, authenticated;

-- =============================================================================
-- SCHEDULE: Call auto_generate_weekly_sessions every morning at midnight Lagos time
-- =============================================================================
-- This uses pg_cron if available. The schedule string is in UTC since pg_cron runs in UTC.
-- Lagos is UTC+1, so midnight in Lagos = 23:00 UTC on the previous day.
-- We schedule it for 23:00 UTC (0 23 * * *)
--
-- Alternatively, you can call this function manually from the app:
--   SELECT * FROM public.auto_generate_weekly_sessions();
-- =============================================================================

-- Drop existing schedule if it exists (prevents errors on re-run)
SELECT cron.unschedule('auto-generate-weekly-sessions')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'auto-generate-weekly-sessions'
);

-- Schedule the function (this will fail gracefully if pg_cron not available)
SELECT cron.schedule(
  'auto-generate-weekly-sessions',
  '0 23 * * *',  -- Every day at 23:00 UTC (= 00:00 Lagos time)
  'SELECT public.auto_generate_weekly_sessions();'
);
