-- =============================================================================
-- Allow cascade delete of attendance records when a member is deleted
-- Version  : 1.0.0
-- Date     : 2026-03-27
--
-- Previously: ON DELETE RESTRICT (members with attendance couldn't be deleted)
-- Now       : ON DELETE CASCADE (deleting a member also deletes their attendance)
--
-- This allows team leaders and admins to delete members at any time,
-- and all their past attendance records will be automatically deleted.
-- =============================================================================

-- Drop the old foreign key constraint with RESTRICT
ALTER TABLE public.clock_ins
  DROP CONSTRAINT clock_ins_member_id_fkey;

-- Add the new foreign key constraint with CASCADE delete
ALTER TABLE public.clock_ins
  ADD CONSTRAINT clock_ins_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES public.members (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
