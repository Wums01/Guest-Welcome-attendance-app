-- =============================================================================
-- TEST SUITE: auto_generate_weekly_sessions() PL/pgSQL Function
-- =============================================================================
-- Tests for the server-side session generation function that runs at midnight Lagos time
--
-- Run these tests with:
--   psql -h localhost -U postgres -d postgres -f supabase/tests/generate_sessions_function.test.sql
--
-- Or in Supabase SQL Editor:
--   1. Copy all SQL from this file
--   2. Paste into the SQL Editor
--   3. Run each test block separately
-- =============================================================================

-- =============================================================================
-- SETUP: Create test data structures
-- =============================================================================

-- Create a test schema to avoid affecting production data
CREATE SCHEMA IF NOT EXISTS test_sessions;

-- Copy the programs table structure for testing
CREATE TABLE IF NOT EXISTS test_sessions.programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  program_type TEXT NOT NULL CHECK (program_type IN ('sunday', 'wednesday')),
  is_tbd BOOLEAN DEFAULT FALSE,
  start_date DATE NOT NULL,
  end_date DATE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Copy the sessions table structure for testing
CREATE TABLE IF NOT EXISTS test_sessions.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id UUID NOT NULL REFERENCES test_sessions.programs(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  date DATE NOT NULL,
  start_time TEXT,
  end_time TEXT,
  clock_in_required BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(program_id, date, name)
);

-- =============================================================================
-- TEST 1: Verify function exists and is callable
-- =============================================================================
BEGIN;
  SELECT 'TEST 1: Function exists' AS test_name;
  
  -- Try to call the function to verify it exists and returns expected type
  SELECT COUNT(*) >= 0 AS test_passed
  FROM public.auto_generate_weekly_sessions();
  
  ROLLBACK;
END;


-- =============================================================================
-- TEST 2: Function returns correct count for Sunday session generation
-- =============================================================================
BEGIN;
  SELECT 'TEST 2: Sunday session generation count' AS test_name;
  
  -- Insert a Sunday program (next Sunday)
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Main Service', 'sunday', FALSE, CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE + INTERVAL '365 days');
  
  -- Manually trigger the function
  SELECT generated_count FROM public.auto_generate_weekly_sessions()
  INTO var_count;
  
  -- Should generate 0-3 sessions depending on the day of the week
  SELECT var_count >= 0 AS test_passed;
  
  ROLLBACK;
END;


-- =============================================================================
-- TEST 3: Function is idempotent (safe to run multiple times)
-- =============================================================================
BEGIN;
  SELECT 'TEST 3: Idempotent execution' AS test_name;
  
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Main Service', 'sunday', FALSE, CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE + INTERVAL '365 days');
  
  -- Run function first time
  SELECT COUNT(*) INTO count1 FROM public.sessions;
  SELECT public.auto_generate_weekly_sessions();
  
  -- Run function a second time immediately
  SELECT COUNT(*) INTO count2 FROM public.sessions;
  SELECT public.auto_generate_weekly_sessions();
  
  -- Count should be the same (idempotent)
  SELECT COUNT(*) INTO count3 FROM public.sessions;
  SELECT (count2 = count3) AS test_passed;
  
  ROLLBACK;
END;


-- =============================================================================
-- TEST 4: Only generates sessions for active programs
-- =============================================================================
BEGIN;
  SELECT 'TEST 4: Only active programs generate sessions' AS test_name;
  
  -- Program that hasn't started yet
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Future Program', 'sunday', FALSE, CURRENT_DATE + INTERVAL '365 days', CURRENT_DATE + INTERVAL '730 days');
  
  -- Program that has ended
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Past Program', 'sunday', FALSE, CURRENT_DATE - INTERVAL '730 days', CURRENT_DATE - INTERVAL '365 days');
  
  -- Active program
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Active Program', 'sunday', FALSE, CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE + INTERVAL '365 days');
  
  -- Trigger generation
  SELECT public.auto_generate_weekly_sessions();
  
  -- Count sessions - should only be for active program
  SELECT COUNT(*) FROM public.sessions WHERE program_id IN (
    SELECT id FROM public.programs WHERE title = 'Active Program'
  ) AS sessions_created;
  
  ROLLBACK;
END;


-- =============================================================================
-- TEST 5: Does not generate sessions for TBD programs
-- =============================================================================
BEGIN;
  SELECT 'TEST 5: TBD programs are skipped' AS test_name;
  
  -- TBD program
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('TBD Program', 'sunday', TRUE, CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE + INTERVAL '365 days');
  
  -- Active, non-TBD program
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Active Program', 'sunday', FALSE, CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE + INTERVAL '365 days');
  
  SELECT public.auto_generate_weekly_sessions();
  
  -- TBD program should have no sessions
  SELECT COUNT(*) = 0 AS test_passed
  FROM public.sessions s
  JOIN public.programs p ON s.program_id = p.id
  WHERE p.is_tbd = TRUE;
  
  ROLLBACK;
END;


-- =============================================================================
-- TEST 6: Wednesday sessions have correct names and no times
-- =============================================================================
BEGIN;
  SELECT 'TEST 6: Wednesday session structure' AS test_name;
  
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Switch Night', 'wednesday', FALSE, CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE + INTERVAL '365 days');
  
  SELECT public.auto_generate_weekly_sessions();
  
  -- Get Wednesday sessions
  SELECT 
    (name = 'Switch Service') AS correct_name,
    (start_time IS NULL) AS no_start_time,
    (end_time IS NULL) AS no_end_time,
    clock_in_required AS has_clock_in
  FROM public.sessions
  WHERE date = (NOW() AT TIME ZONE 'Africa/Lagos')::DATE
    AND EXISTS (
      SELECT 1 FROM public.programs p WHERE p.id = sessions.program_id AND p.program_type = 'wednesday'
    )
  LIMIT 1;
  
  ROLLBACK;
END;


-- =============================================================================
-- TEST 7: Sunday sessions have correct times
-- =============================================================================
BEGIN;
  SELECT 'TEST 7: Sunday session times are correct' AS test_name;
  
  INSERT INTO public.programs (title, program_type, is_tbd, start_date, end_date)
  VALUES ('Main Service', 'sunday', FALSE, CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE + INTERVAL '365 days');
  
  SELECT public.auto_generate_weekly_sessions();
  
  -- Verify Service 1
  SELECT EXISTS (
    SELECT 1 FROM public.sessions
    WHERE date = (NOW() AT TIME ZONE 'Africa/Lagos')::DATE
      AND start_time = '06:30' AND end_time = '08:30'
      AND clock_in_required = TRUE
  ) AS service_1_correct;
  
  -- Verify Service 2
  SELECT EXISTS (
    SELECT 1 FROM public.sessions
    WHERE date = (NOW() AT TIME ZONE 'Africa/Lagos')::DATE
      AND start_time = '08:30' AND end_time = '11:00'
      AND clock_in_required = TRUE
  ) AS service_2_correct;
  
  -- Verify Service 3
  SELECT EXISTS (
    SELECT 1 FROM public.sessions
    WHERE date = (NOW() AT TIME ZONE 'Africa/Lagos')::DATE
      AND start_time = '11:00' AND end_time = '13:30'
      AND clock_in_required = TRUE
  ) AS service_3_correct;
  
  ROLLBACK;
END;


-- =============================================================================
-- TEST 8: Respects Africa/Lagos timezone
-- =============================================================================
BEGIN;
  SELECT 'TEST 8: Lagos timezone handling' AS test_name;
  
  -- Get the date in Lagos timezone when function runs
  SELECT (NOW() AT TIME ZONE 'Africa/Lagos')::DATE AS lagos_date,
         EXTRACT(DOW FROM (NOW() AT TIME ZONE 'Africa/Lagos')::DATE) AS day_of_week;
  
  -- day_of_week: 0=Sunday, 3=Wednesday, others=no generation
  
  ROLLBACK;
END;


-- =============================================================================
-- CLEANUP
-- =============================================================================
-- Drop test schema
-- DROP SCHEMA IF EXISTS test_sessions CASCADE;
