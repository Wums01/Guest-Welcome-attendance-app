-- =============================================================================
-- pgTAP tests: session_generation.test.sql
-- =============================================================================
-- Run with:  supabase test db
--
-- These tests verify that the Sunday/Wednesday session auto-generation works
-- correctly end-to-end.  All test data is created inside a transaction that
-- is rolled back at the end, so the tests never pollute the real database.
-- =============================================================================

BEGIN;

SELECT plan(28);  -- total number of test assertions below

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Next occurrence of a specific weekday (0=Sun, 3=Wed) from a base date
CREATE OR REPLACE FUNCTION _next_weekday(base DATE, target_dow INT)
RETURNS DATE LANGUAGE sql AS $$
  SELECT base + ((target_dow - EXTRACT(DOW FROM base)::INT + 7) % 7 + 1)::INT;
$$;

-- Known upcoming Sunday and Wednesday relative to a fixed test base date
-- Using a fixed date avoids flakiness from the real clock.
-- 2026-01-04 is a Sunday; 2026-01-07 is a Wednesday.
DO $$ BEGIN
  ASSERT _next_weekday('2026-01-03', 0) = '2026-01-04', 'helper: next Sunday';
  ASSERT _next_weekday('2026-01-03', 3) = '2026-01-07', 'helper: next Wednesday';
END; $$;

-- ── 1. Functions exist ────────────────────────────────────────────────────────

SELECT has_function(
  'public', 'generate_weekly_sessions_for_date',
  ARRAY['date'],
  'generate_weekly_sessions_for_date(date) function exists'
);

SELECT has_function(
  'public', 'auto_generate_weekly_sessions',
  ARRAY[]::text[],
  'auto_generate_weekly_sessions() function exists'
);

SELECT has_function(
  'public', 'verify_session_generation',
  ARRAY[]::text[],
  'verify_session_generation() helper function exists'
);

-- ── 2. Test setup: insert a Sunday program and a Wednesday program ─────────────

INSERT INTO public.programs (id, title, program_type, is_tbd, start_date, end_date, is_virtual)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Test Sunday Service',    'sunday',    FALSE, '2025-01-01', '2027-12-31', FALSE),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Test Wednesday Switch',  'wednesday', FALSE, '2025-01-01', '2027-12-31', FALSE),
  -- TBD program: should NOT get sessions generated
  ('aaaaaaaa-0000-0000-0000-000000000003', 'Test TBD Program',       'sunday',    TRUE,  NULL,         NULL,         FALSE),
  -- Expired program: end_date in the past, should NOT get sessions
  ('aaaaaaaa-0000-0000-0000-000000000004', 'Test Expired Sunday',    'sunday',    FALSE, '2025-01-01', '2025-06-30', FALSE),
  -- Future program: start_date in the future, should NOT get sessions
  ('aaaaaaaa-0000-0000-0000-000000000005', 'Test Future Sunday',     'sunday',    FALSE, '2030-01-01', '2031-12-31', FALSE);

-- ── 3. Sunday generation ──────────────────────────────────────────────────────

-- Test date: 2026-01-04 (known Sunday)
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-04') $$,
  $$ VALUES (3) $$,
  'generate_weekly_sessions_for_date on a Sunday creates 3 sessions for 1 active Sunday program'
);

SELECT is(
  (SELECT COUNT(*) FROM public.sessions
   WHERE date = '2026-01-04'
     AND program_id = 'aaaaaaaa-0000-0000-0000-000000000001')::INT,
  3,
  '3 sessions exist in sessions table for the test Sunday program'
);

SELECT set_eq(
  $$ SELECT name FROM public.sessions
     WHERE date = '2026-01-04' AND program_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     ORDER BY name $$,
  $$ VALUES ('Service 1'), ('Service 2'), ('Service 3') $$,
  'Sunday sessions are named Service 1, Service 2, Service 3'
);

SELECT results_eq(
  $$ SELECT start_time, end_time FROM public.sessions
     WHERE date = '2026-01-04' AND name = 'Service 1'
       AND program_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  $$ VALUES ('06:30'::TEXT, '08:20'::TEXT) $$,
  'Service 1 has correct time 06:30–08:20'
);

SELECT results_eq(
  $$ SELECT start_time, end_time FROM public.sessions
     WHERE date = '2026-01-04' AND name = 'Service 2'
       AND program_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  $$ VALUES ('08:30'::TEXT, '10:20'::TEXT) $$,
  'Service 2 has correct time 08:30–10:20'
);

SELECT results_eq(
  $$ SELECT start_time, end_time FROM public.sessions
     WHERE date = '2026-01-04' AND name = 'Service 3'
       AND program_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  $$ VALUES ('10:30'::TEXT, '12:00'::TEXT) $$,
  'Service 3 has correct time 10:30–12:00'
);

-- ── 4. Sunday idempotency ─────────────────────────────────────────────────────

-- Calling again for the same date should create 0 new sessions
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-04') $$,
  $$ VALUES (0) $$,
  'Second call on same Sunday returns 0 (idempotent — no duplicates)'
);

SELECT is(
  (SELECT COUNT(*) FROM public.sessions
   WHERE date = '2026-01-04'
     AND program_id = 'aaaaaaaa-0000-0000-0000-000000000001')::INT,
  3,
  'Still exactly 3 sessions after second call (no duplicates created)'
);

-- ── 5. Wednesday generation ───────────────────────────────────────────────────

-- Test date: 2026-01-07 (known Wednesday)
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-07') $$,
  $$ VALUES (1) $$,
  'generate_weekly_sessions_for_date on a Wednesday creates 1 session for 1 active Wednesday program'
);

SELECT is(
  (SELECT COUNT(*) FROM public.sessions
   WHERE date = '2026-01-07'
     AND program_id = 'aaaaaaaa-0000-0000-0000-000000000002')::INT,
  1,
  '1 session exists in sessions table for the test Wednesday program'
);

SELECT results_eq(
  $$ SELECT name FROM public.sessions
     WHERE date = '2026-01-07'
       AND program_id = 'aaaaaaaa-0000-0000-0000-000000000002' $$,
  $$ VALUES ('Switch Service') $$,
  'Wednesday session is named Switch Service'
);

-- Wednesday idempotency
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-07') $$,
  $$ VALUES (0) $$,
  'Second call on same Wednesday returns 0 (idempotent)'
);

-- ── 6. Non-service day returns 0 ──────────────────────────────────────────────

-- 2026-01-05 is a Monday
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-05') $$,
  $$ VALUES (0) $$,
  'Monday returns 0 sessions — not a service day'
);

-- 2026-01-06 is a Tuesday
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-06') $$,
  $$ VALUES (0) $$,
  'Tuesday returns 0 sessions — not a service day'
);

-- 2026-01-08 is a Thursday
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-08') $$,
  $$ VALUES (0) $$,
  'Thursday returns 0 sessions — not a service day'
);

-- ── 7. TBD program is excluded ────────────────────────────────────────────────

-- 2026-01-11 is a Sunday; only the non-TBD program (id=001) should get sessions
SELECT results_eq(
  $$ SELECT public.generate_weekly_sessions_for_date('2026-01-11') $$,
  $$ VALUES (3) $$,
  'TBD program is excluded: only the non-TBD Sunday program gets sessions'
);

SELECT is(
  (SELECT COUNT(*) FROM public.sessions
   WHERE date = '2026-01-11'
     AND program_id = 'aaaaaaaa-0000-0000-0000-000000000003')::INT,
  0,
  'TBD program (id=003) has 0 sessions generated'
);

-- ── 8. Expired / future programs are excluded ─────────────────────────────────

-- 2026-01-11 is a Sunday — expired program (end_date=2025-06-30) gets nothing
SELECT is(
  (SELECT COUNT(*) FROM public.sessions
   WHERE date = '2026-01-11'
     AND program_id = 'aaaaaaaa-0000-0000-0000-000000000004')::INT,
  0,
  'Expired program (end_date in past) gets 0 sessions'
);

-- Future program (start_date=2030) gets nothing
SELECT is(
  (SELECT COUNT(*) FROM public.sessions
   WHERE date = '2026-01-11'
     AND program_id = 'aaaaaaaa-0000-0000-0000-000000000005')::INT,
  0,
  'Future program (start_date in future) gets 0 sessions'
);

-- ── 9. auto_generate_weekly_sessions backfill ─────────────────────────────────
-- The function has a 14-day lookback. Call it and confirm it returns a result
-- (we can't assert the exact count because we don't know what the real clock says,
-- but we can assert it returns a row with a non-negative count).

SELECT ok(
  (SELECT (data->>'generated_count')::INT >= 0
   FROM (
     SELECT to_json(x) AS data
     FROM public.auto_generate_weekly_sessions() AS x(generated_count)
   ) sub
   LIMIT 1),
  'auto_generate_weekly_sessions() returns a non-negative generated_count'
);

-- ── 10. verify_session_generation returns expected columns ────────────────────

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.verify_session_generation()
    WHERE check_name = 'lagos_date'
  ),
  'verify_session_generation() includes a lagos_date row'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.verify_session_generation()
    WHERE check_name = 'is_service_day'
  ),
  'verify_session_generation() includes an is_service_day row'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.verify_session_generation()
    WHERE check_name = 'cron_job_scheduled'
  ),
  'verify_session_generation() includes a cron_job_scheduled row'
);

-- ── 11. clock_in_required defaults to TRUE ────────────────────────────────────

SELECT is(
  (SELECT clock_in_required FROM public.sessions
   WHERE date = '2026-01-04' AND name = 'Service 1'
     AND program_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  TRUE,
  'Generated sessions have clock_in_required = TRUE'
);

SELECT * FROM finish();

ROLLBACK;
