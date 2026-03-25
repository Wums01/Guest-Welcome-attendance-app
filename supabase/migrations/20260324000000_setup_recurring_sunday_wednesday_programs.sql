-- =============================================================================
-- Setup Recurring Sunday and Wednesday Programs
-- =============================================================================
-- Purpose:
--   Create the recurring programs required for auto-session generation.
--   Without these programs, auto_generate_weekly_sessions() returns 0.
--
-- Usage:
--   Run this migration to set up:
--   1. Sunday Services program (creates 3 services every Sunday)
--   2. Wednesday Switch program (creates 1 service every Wednesday)
--
-- Note:
--   These dates cover 2026-2027. Adjust end_date as needed for your use case.
--   The auto-generation function will create sessions for all Sundays/Wednesdays
--   that fall within the start_date to end_date range.
-- =============================================================================

-- Ensure the programs don't already exist (idempotent)
DELETE FROM public.programs
WHERE title IN ('Sunday Services', 'Wednesday Switch')
  AND program_type IN ('sunday', 'wednesday');

-- Create recurring Sunday program (creates 3 services per Sunday)
INSERT INTO public.programs (
  id,
  title,
  program_type,
  is_tbd,
  start_date,
  end_date,
  team_scope,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  'Sunday Services',
  'sunday',
  FALSE,
  '2026-01-01',
  '2027-12-31',
  'all',
  NOW(),
  NOW()
);

-- Create recurring Wednesday program (creates 1 Switch Service per Wednesday)
INSERT INTO public.programs (
  id,
  title,
  program_type,
  is_tbd,
  start_date,
  end_date,
  team_scope,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  'Wednesday Switch',
  'wednesday',
  FALSE,
  '2026-01-01',
  '2027-12-31',
  'all',
  NOW(),
  NOW()
);

-- Trigger auto-generation for the next 14 days to backfill any missed sessions
SELECT public.auto_generate_weekly_sessions();
