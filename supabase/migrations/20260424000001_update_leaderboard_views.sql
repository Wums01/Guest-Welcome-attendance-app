-- supabase/migrations/20260424000001_update_leaderboard_views.sql
-- Replace present_count ranking with total_points from points_ledger.

DROP VIEW IF EXISTS public.monthly_leaderboard;
DROP VIEW IF EXISTS public.yearly_leaderboard;

CREATE VIEW public.monthly_leaderboard AS
SELECT
  to_char(s.date, 'YYYY-MM') AS year_month,
  m.id                        AS member_id,
  m.full_name,
  m.team,
  m.offline_code,
  COALESCE(SUM(pl.points), 0)::INT AS present_count,
  COALESCE(SUM(pl.points), 0)::INT AS total_points
FROM public.members m
LEFT JOIN public.points_ledger pl ON pl.member_id = m.id
LEFT JOIN public.sessions s       ON s.id = pl.session_id
GROUP BY to_char(s.date, 'YYYY-MM'), m.id, m.full_name, m.team, m.offline_code;

CREATE VIEW public.yearly_leaderboard AS
SELECT
  to_char(s.date, 'YYYY') AS year,
  m.id                     AS member_id,
  m.full_name,
  m.team,
  m.offline_code,
  COALESCE(SUM(pl.points), 0)::INT AS present_count,
  COALESCE(SUM(pl.points), 0)::INT AS total_points
FROM public.members m
LEFT JOIN public.points_ledger pl ON pl.member_id = m.id
LEFT JOIN public.sessions s       ON s.id = pl.session_id
GROUP BY to_char(s.date, 'YYYY'), m.id, m.full_name, m.team, m.offline_code;
