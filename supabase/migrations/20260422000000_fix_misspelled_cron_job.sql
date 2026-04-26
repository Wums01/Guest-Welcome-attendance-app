-- =============================================================================
-- Unschedule misspelled cron job and schedule correct job
-- =============================================================================
-- This migration safely removes any incorrectly named pg_cron job (typos)
-- and schedules the correct job that calls the RPC `public.auto_generate_weekly_sessions()`.
-- It is safe to run even if pg_cron is not installed.

DO $$
BEGIN
  -- Only attempt if pg_cron extension is present
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      -- Try to unschedule common misspelled job names that were observed
      PERFORM cron.unschedule('auto-generate-weekly-sessior');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    BEGIN
      PERFORM cron.unschedule('auto-generate-weekly-sessions');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    -- Schedule the correct job (idempotent: cron.schedule will create a new job)
    PERFORM cron.schedule(
      'auto-generate-weekly-sessions',
      '0 23 * * *',
      'SELECT public.auto_generate_weekly_sessions();'
    );

    RAISE NOTICE 'Ensured pg_cron job "auto-generate-weekly-sessions" scheduled at 23:00 UTC.';
  ELSE
    RAISE NOTICE 'pg_cron extension not present - skipping cron scheduling.';
  END IF;
END;
$$;
