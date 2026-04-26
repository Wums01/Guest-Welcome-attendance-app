-- supabase/migrations/20260424000004_create_device_tokens.sql
-- Stores FCM device tokens per staff member.
-- Used by Edge Functions to send push notifications to all active staff devices.

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id   UUID NOT NULL REFERENCES public.staff_users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL UNIQUE,
  platform   TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS device_tokens_staff_idx
  ON public.device_tokens (staff_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY device_tokens_authenticated
  ON public.device_tokens FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY device_tokens_anon
  ON public.device_tokens FOR ALL TO anon
  USING (true) WITH CHECK (true);
