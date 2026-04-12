-- Allow staff users to be deleted even if they have follow-up action records.
-- Changes created_by_staff_id from NOT NULL / ON DELETE RESTRICT
-- to nullable / ON DELETE SET NULL so the audit trail is preserved.

ALTER TABLE public.member_follow_up_actions
  DROP CONSTRAINT member_follow_up_actions_created_by_staff_id_fkey;

ALTER TABLE public.member_follow_up_actions
  ALTER COLUMN created_by_staff_id DROP NOT NULL;

ALTER TABLE public.member_follow_up_actions
  ADD CONSTRAINT member_follow_up_actions_created_by_staff_id_fkey
    FOREIGN KEY (created_by_staff_id)
    REFERENCES public.staff_users (id)
    ON DELETE SET NULL;
