-- =============================================================================
-- Allow the anon role to read and write app settings.
--
-- The app uses the Supabase anon key without an auth flow, so operations
-- run as the "anon" role.  The previous policy only covered "authenticated",
-- which caused a 42501 RLS error on every settings read/write.
-- =============================================================================

CREATE POLICY "anon_full_access" ON public.settings
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- Ensure the seed row exists in case the initial migration was applied
-- without its INSERT (e.g. the table was created in the Supabase dashboard).
INSERT INTO public.settings (key, value)
VALUES ('test_mode_enabled', 'false')
ON CONFLICT (key) DO NOTHING;
