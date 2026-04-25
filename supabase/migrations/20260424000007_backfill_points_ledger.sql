-- supabase/migrations/20260424000007_backfill_points_ledger.sql
-- One-time backfill: award 1 point for every existing 'present' clock_in
-- that doesn't yet have an entry in points_ledger.

INSERT INTO public.points_ledger (member_id, session_id, points, reason, awarded_at)
SELECT
  ci.member_id,
  ci.session_id,
  1,
  'attendance',
  ci.clocked_at
FROM public.clock_ins ci
WHERE ci.status = 'present'
ON CONFLICT (member_id, session_id) DO NOTHING;
