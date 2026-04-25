-- supabase/migrations/20260424000009_fix_leaderboard_views.sql
--
-- Fix leaderboard views so they work regardless of whether points_ledger
-- has been backfilled.  The previous version (20260424000001) joined
-- members → points_ledger → sessions, meaning members with no ledger rows
-- got year_month = NULL and were excluded from every monthly filter — making
-- every count return 0.
--
-- New approach:
--   • Drive the query from clock_ins (guaranteed to have data) so that
--     present_count is always accurate.
--   • LEFT JOIN points_ledger to pick up custom point values; fall back to
--     present_count when no ledger row exists yet.
--
-- Also fixes session_attendance_summary: COUNT(*) with LEFT JOIN returned 1
-- for sessions that had zero clock-ins.  Changed to COUNT(ci.id).

-- ── session_attendance_summary ────────────────────────────────────────────────

DROP VIEW IF EXISTS public.session_attendance_summary;

CREATE VIEW public.session_attendance_summary AS
SELECT
  s.id                                            AS session_id,
  s.name                                          AS session_name,
  s.date                                          AS session_date,
  p.id                                            AS program_id,
  p.title                                         AS program_title,
  s.new_guest_count                               AS new_guest_count,
  COUNT(ci.id) FILTER (WHERE ci.status = 'present') AS present_count,
  COUNT(ci.id) FILTER (WHERE ci.status = 'absent')  AS absent_count,
  COUNT(ci.id) FILTER (WHERE ci.status = 'excused') AS excused_count,
  COUNT(ci.id)                                      AS total_marked
FROM public.sessions s
JOIN  public.programs  p  ON p.id  = s.program_id
LEFT JOIN public.clock_ins ci ON ci.session_id = s.id
GROUP BY s.id, s.name, s.date, p.id, p.title, s.new_guest_count;

-- ── monthly_leaderboard ───────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.monthly_leaderboard;

CREATE VIEW public.monthly_leaderboard AS
SELECT
  to_char(s.date, 'YYYY-MM')                                AS year_month,
  m.id                                                       AS member_id,
  m.full_name,
  m.team,
  m.offline_code,
  COUNT(ci.id)                                               AS present_count,
  COALESCE(
    SUM(pl.points),
    COUNT(ci.id)
  )::INT                                                     AS total_points
FROM  public.clock_ins     ci
JOIN  public.members       m  ON m.id  = ci.member_id
JOIN  public.sessions      s  ON s.id  = ci.session_id
LEFT JOIN public.points_ledger pl
       ON pl.member_id = ci.member_id
      AND pl.session_id = ci.session_id
WHERE ci.status = 'present'
GROUP BY to_char(s.date, 'YYYY-MM'),
         m.id, m.full_name, m.team, m.offline_code;

-- ── yearly_leaderboard ────────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.yearly_leaderboard;

CREATE VIEW public.yearly_leaderboard AS
SELECT
  to_char(s.date, 'YYYY')                                    AS year,
  m.id                                                        AS member_id,
  m.full_name,
  m.team,
  m.offline_code,
  COUNT(ci.id)                                                AS present_count,
  COALESCE(
    SUM(pl.points),
    COUNT(ci.id)
  )::INT                                                      AS total_points
FROM  public.clock_ins     ci
JOIN  public.members       m  ON m.id  = ci.member_id
JOIN  public.sessions      s  ON s.id  = ci.session_id
LEFT JOIN public.points_ledger pl
       ON pl.member_id = ci.member_id
      AND pl.session_id = ci.session_id
WHERE ci.status = 'present'
GROUP BY to_char(s.date, 'YYYY'),
         m.id, m.full_name, m.team, m.offline_code;
