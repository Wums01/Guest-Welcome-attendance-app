-- =============================================================================
-- Backfill missed weekly sessions and align Sunday service times
-- =============================================================================
-- Why:
--   1. If pg_cron does not run at midnight, sessions should still be created
--      automatically the next time the app calls the RPC.
--   2. Sunday session times were updated by the client.
--
-- What this migration does:
--   - Adds a helper that generates Sunday/Wednesday sessions for a specific date
--   - Replaces auto_generate_weekly_sessions() with a lookback/backfill version
--   - Updates upcoming Sunday sessions to the new requested time slots
-- =============================================================================

CREATE OR REPLACE FUNCTION public.generate_weekly_sessions_for_date(
  p_target_date DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_program RECORD;
  v_created_count INTEGER := 0;
BEGIN
  -- Sunday programs create 3 services for the given Sunday date.
  IF EXTRACT(DOW FROM p_target_date) = 0 THEN
    FOR v_program IN
      SELECT p.id
      FROM public.programs p
      WHERE
        p.program_type = 'sunday'
        AND p.is_tbd = FALSE
        AND p.start_date <= p_target_date
        AND (p.end_date IS NULL OR p.end_date >= p_target_date)
        AND NOT EXISTS (
          SELECT 1
          FROM public.sessions s
          WHERE s.program_id = p.id
            AND s.date = p_target_date
        )
    LOOP
      INSERT INTO public.sessions (
        program_id,
        name,
        date,
        start_time,
        end_time,
        clock_in_required
      )
      VALUES
        (v_program.id, 'Service 1', p_target_date, '06:30', '08:20', TRUE),
        (v_program.id, 'Service 2', p_target_date, '08:30', '10:20', TRUE),
        (v_program.id, 'Service 3', p_target_date, '10:30', '12:00', TRUE);

      v_created_count := v_created_count + 3;
    END LOOP;
  END IF;

  -- Wednesday programs create one Switch Service for the given Wednesday date.
  IF EXTRACT(DOW FROM p_target_date) = 3 THEN
    FOR v_program IN
      SELECT p.id
      FROM public.programs p
      WHERE
        p.program_type = 'wednesday'
        AND p.is_tbd = FALSE
        AND p.start_date <= p_target_date
        AND (p.end_date IS NULL OR p.end_date >= p_target_date)
        AND NOT EXISTS (
          SELECT 1
          FROM public.sessions s
          WHERE s.program_id = p.id
            AND s.date = p_target_date
        )
    LOOP
      INSERT INTO public.sessions (
        program_id,
        name,
        date,
        clock_in_required
      )
      VALUES (v_program.id, 'Switch Service', p_target_date, TRUE);

      v_created_count := v_created_count + 1;
    END LOOP;
  END IF;

  RETURN v_created_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.auto_generate_weekly_sessions()
RETURNS TABLE (generated_count INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_lagos_today DATE := (NOW() AT TIME ZONE 'Africa/Lagos')::DATE;
  v_target_date DATE;
  v_total_generated INT := 0;
BEGIN
  -- Backfill the last 14 days so missed Sunday/Wednesday sessions are created
  -- automatically the next time the app or scheduler triggers this RPC.
  v_target_date := v_lagos_today - 14;

  WHILE v_target_date <= v_lagos_today LOOP
    v_total_generated :=
      v_total_generated + public.generate_weekly_sessions_for_date(v_target_date);
    v_target_date := v_target_date + 1;
  END LOOP;

  RETURN QUERY SELECT v_total_generated;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_weekly_sessions_for_date(DATE)
  TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.auto_generate_weekly_sessions()
  TO anon, authenticated;

-- Align upcoming Sunday sessions with the newly approved time slots.
UPDATE public.sessions
SET
  start_time = '06:30',
  end_time = '08:20'
WHERE name = 'Service 1'
  AND date >= ((NOW() AT TIME ZONE 'Africa/Lagos')::DATE);

UPDATE public.sessions
SET
  start_time = '08:30',
  end_time = '10:20'
WHERE name = 'Service 2'
  AND date >= ((NOW() AT TIME ZONE 'Africa/Lagos')::DATE);

UPDATE public.sessions
SET
  start_time = '10:30',
  end_time = '12:00'
WHERE name = 'Service 3'
  AND date >= ((NOW() AT TIME ZONE 'Africa/Lagos')::DATE);
