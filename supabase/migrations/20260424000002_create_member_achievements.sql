-- supabase/migrations/20260424000002_create_member_achievements.sql

CREATE TABLE IF NOT EXISTS public.member_achievements (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id        UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  achievement_type TEXT NOT NULL,
  achieved_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  metadata         JSONB NULL,
  CONSTRAINT member_achievements_type_check CHECK (
    achievement_type IN (
      'streak_4', 'streak_8', 'streak_16',
      'tier_bronze', 'tier_silver', 'tier_gold', 'tier_platinum',
      'perfect_month',
      'anniversary_1yr', 'anniversary_2yr'
    )
  )
);

-- Unique per type per member, EXCEPT perfect_month which is unique per year-month
CREATE UNIQUE INDEX IF NOT EXISTS member_achievements_unique_type
  ON public.member_achievements (member_id, achievement_type)
  WHERE achievement_type != 'perfect_month';

CREATE UNIQUE INDEX IF NOT EXISTS member_achievements_unique_perfect_month
  ON public.member_achievements (member_id, achievement_type, (metadata->>'year_month'))
  WHERE achievement_type = 'perfect_month';

CREATE INDEX IF NOT EXISTS member_achievements_member_idx
  ON public.member_achievements (member_id, achieved_at DESC);

ALTER TABLE public.member_achievements ENABLE ROW LEVEL SECURITY;

CREATE POLICY member_achievements_authenticated
  ON public.member_achievements FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY member_achievements_anon
  ON public.member_achievements FOR ALL TO anon
  USING (true) WITH CHECK (true);

-- Returns the current consecutive Sunday streak for a member.
-- Counts backwards from the most recent Sunday session.
CREATE OR REPLACE FUNCTION public.get_member_streak(p_member_id UUID)
RETURNS INT AS $$
DECLARE
  v_streak INT := 0;
  v_row    RECORD;
BEGIN
  FOR v_row IN
    SELECT ci.status
    FROM public.clock_ins ci
    JOIN public.sessions s ON s.id = ci.session_id
    WHERE ci.member_id = p_member_id
      AND EXTRACT(DOW FROM s.date) = 0  -- Sunday only
    ORDER BY s.date DESC
  LOOP
    IF v_row.status = 'present' THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;
  RETURN v_streak;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
