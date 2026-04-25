-- supabase/migrations/20260424000003_extend_follow_up_actions.sql
-- Rename action → action_type, broaden the CHECK constraint,
-- add scheduled_follow_up_at and outcome_note columns.

-- 1. Rename the column
ALTER TABLE public.member_follow_up_actions
  RENAME COLUMN action TO action_type;

-- 2. Drop old single-value CHECK constraint
ALTER TABLE public.member_follow_up_actions
  DROP CONSTRAINT IF EXISTS member_follow_up_actions_action_check;

-- 3. Add new CHECK with all allowed values
ALTER TABLE public.member_follow_up_actions
  ADD CONSTRAINT member_follow_up_actions_action_type_check
  CHECK (action_type IN (
    'contacted',
    'not_reachable',
    'returned',
    'transferred_out',
    'needs_visit'
  ));

-- 4. Add new columns
ALTER TABLE public.member_follow_up_actions
  ADD COLUMN IF NOT EXISTS scheduled_follow_up_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS outcome_note TEXT NULL;

-- 5. Index for daily reminder query
CREATE INDEX IF NOT EXISTS member_follow_up_actions_scheduled_idx
  ON public.member_follow_up_actions (scheduled_follow_up_at)
  WHERE scheduled_follow_up_at IS NOT NULL;
