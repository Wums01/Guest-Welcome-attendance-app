-- =============================================================================
-- Add manual "new guest" counts to sessions
--
-- Allows staff to enter how many new guests attended each session (e.g. Sunday
-- services). This number is stored on the session and surfaced in reports.
--
-- NOTE: Existing sessions will default to 0.
-- =============================================================================

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS new_guest_count INTEGER NOT NULL DEFAULT 0;

-- Update the attendance summary view to include the new guest count.
-- This view is used by the app reports.

DROP VIEW IF EXISTS public.session_attendance_summary;

CREATE VIEW public.session_attendance_summary AS
SELECT
  s.id                                          AS session_id,
  s.name                                        AS session_name,
  s.date                                        AS session_date,
  p.id                                          AS program_id,
  p.title                                       AS program_title,
  s.new_guest_count                             AS new_guest_count,
  COUNT(*) FILTER (WHERE ci.status = 'present') AS present_count,
  COUNT(*) FILTER (WHERE ci.status = 'absent')  AS absent_count,
  COUNT(*) FILTER (WHERE ci.status = 'excused') AS excused_count,
  COUNT(*)                                      AS total_marked
FROM public.sessions s
JOIN public.programs p ON p.id = s.program_id
LEFT JOIN public.clock_ins ci ON ci.session_id = s.id
GROUP BY s.id, s.name, s.date, p.id, p.title, s.new_guest_count;
