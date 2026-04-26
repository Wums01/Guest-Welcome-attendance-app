-- supabase/migrations/20260424000000_create_points_ledger.sql
-- Append-only ledger: one row per (member, session) attendance point.
-- A DB trigger fires on clock_ins INSERT/UPDATE to award the point.

CREATE TABLE IF NOT EXISTS public.points_ledger (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id   UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  session_id  UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  points      INT NOT NULL DEFAULT 1,
  reason      TEXT NOT NULL DEFAULT 'attendance',
  awarded_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (member_id, session_id)
);

CREATE INDEX IF NOT EXISTS points_ledger_member_idx
  ON public.points_ledger (member_id);

ALTER TABLE public.points_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY points_ledger_authenticated
  ON public.points_ledger FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY points_ledger_anon
  ON public.points_ledger FOR ALL TO anon
  USING (true) WITH CHECK (true);

-- Trigger function: insert 1 point when a clock_in becomes 'present'
CREATE OR REPLACE FUNCTION public.award_attendance_point()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'present' THEN
    INSERT INTO public.points_ledger (member_id, session_id, points, reason)
    VALUES (NEW.member_id, NEW.session_id, 1, 'attendance')
    ON CONFLICT (member_id, session_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fire on INSERT and on UPDATE (e.g. absent → present)
DROP TRIGGER IF EXISTS trigger_award_attendance_point ON public.clock_ins;
CREATE TRIGGER trigger_award_attendance_point
  AFTER INSERT OR UPDATE OF status ON public.clock_ins
  FOR EACH ROW EXECUTE FUNCTION public.award_attendance_point();
