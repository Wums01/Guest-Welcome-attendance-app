-- =============================================================================
-- Add anon role access to all tables.
--
-- The app uses the Supabase anon key with no login screen, so every
-- operation runs as the "anon" role.  The initial schema only created
-- "authenticated_full_access" policies, which caused 42501 errors on
-- every INSERT / UPDATE / DELETE from the app.
-- =============================================================================

CREATE POLICY "anon_full_access" ON public.members
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_full_access" ON public.programs
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_full_access" ON public.sessions
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_full_access" ON public.clock_ins
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- settings may already have this policy from migration 20260312000002;
-- the DO $$ block avoids an error if it already exists.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'settings'
      AND policyname = 'anon_full_access'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "anon_full_access" ON public.settings
        FOR ALL TO anon USING (true) WITH CHECK (true)
    $policy$;
  END IF;
END;
$$;

-- Ensure default seed row exists
INSERT INTO public.settings (key, value)
VALUES ('test_mode_enabled', 'false')
ON CONFLICT (key) DO NOTHING;
