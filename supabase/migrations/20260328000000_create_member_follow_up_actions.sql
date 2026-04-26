-- Persist follow-up actions for absent members.
-- This lets the app hide members from active follow-up once staff have
-- contacted them, while keeping an audit trail of who dismissed the item.

CREATE TABLE IF NOT EXISTS public.member_follow_up_actions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id           UUID NOT NULL
                      REFERENCES public.members (id)
                      ON DELETE CASCADE,
  action              TEXT NOT NULL
                      CHECK (action IN ('contacted')),
  created_by_staff_id UUID NOT NULL
                      REFERENCES public.staff_users (id)
                      ON DELETE RESTRICT,
  note                TEXT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS member_follow_up_actions_member_created_idx
  ON public.member_follow_up_actions (member_id, created_at DESC);

CREATE INDEX IF NOT EXISTS member_follow_up_actions_staff_idx
  ON public.member_follow_up_actions (created_by_staff_id);

ALTER TABLE public.member_follow_up_actions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'member_follow_up_actions'
      AND policyname = 'authenticated_full_access_follow_up_actions'
  ) THEN
    CREATE POLICY authenticated_full_access_follow_up_actions
      ON public.member_follow_up_actions
      FOR ALL
      TO authenticated
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'member_follow_up_actions'
      AND policyname = 'anon_full_access_follow_up_actions'
  ) THEN
    CREATE POLICY anon_full_access_follow_up_actions
      ON public.member_follow_up_actions
      FOR ALL
      TO anon
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
