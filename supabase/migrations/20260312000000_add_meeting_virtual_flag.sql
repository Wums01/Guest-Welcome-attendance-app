-- supabase/migrations/20260312000000_add_meeting_virtual_flag.sql
--
-- Adds `is_virtual` flag to programs table.
-- Used to distinguish physical vs virtual meetings/trainings.
-- Defaults to FALSE so existing records are unaffected.

ALTER TABLE public.programs
  ADD COLUMN IF NOT EXISTS is_virtual BOOLEAN NOT NULL DEFAULT FALSE;
