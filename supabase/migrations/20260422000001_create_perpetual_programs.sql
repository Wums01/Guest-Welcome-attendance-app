-- =============================================================================
-- Create perpetual recurring Sunday and Wednesday programs
-- =============================================================================
-- FIX: The one-off programs (expired April 15-19) must be replaced with:
--   1. "Sunday Services" - recurring every Sunday from 2026-01-01 to 2027-12-31
--   2. "Wednesday Switch" - recurring every Wednesday from 2026-01-01 to 2027-12-31
--
-- The cron job calls auto_generate_weekly_sessions() which needs these
-- perpetual programs to exist with active date ranges.

-- Step 1: Delete all expired one-off programs (keep nothing that has end_date in the past)
DELETE FROM public.programs
WHERE program_type IN ('sunday', 'wednesday')
  AND (end_date < NOW()::DATE OR (start_date = end_date AND start_date != NOW()::DATE));

-- Step 2: Ensure perpetual programs exist (idempotent - delete then recreate)
DELETE FROM public.programs
WHERE title IN ('Sunday Services', 'Wednesday Switch')
  AND program_type IN ('sunday', 'wednesday');

-- Step 3: Create perpetual Sunday Services program
INSERT INTO public.programs (
  title,
  program_type,
  is_tbd,
  start_date,
  end_date
)
VALUES (
  'Sunday Services',
  'sunday',
  FALSE,
  '2026-01-01',
  '2027-12-31'
);

-- Step 4: Create perpetual Wednesday Switch program
INSERT INTO public.programs (
  title,
  program_type,
  is_tbd,
  start_date,
  end_date
)
VALUES (
  'Wednesday Switch',
  'wednesday',
  FALSE,
  '2026-01-01',
  '2027-12-31'
);

-- Step 5: Trigger immediate generation to test
SELECT public.auto_generate_weekly_sessions();
