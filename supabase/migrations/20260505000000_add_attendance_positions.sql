-- Add position assignment support for attendance records.

ALTER TABLE public.clock_ins
  ADD COLUMN IF NOT EXISTS position_label TEXT;

CREATE INDEX IF NOT EXISTS clock_ins_session_position_idx
  ON public.clock_ins (session_id, position_label)
  WHERE position_label IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.program_position_options (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  program_id UUID NOT NULL,
  label TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT program_position_options_pkey PRIMARY KEY (id),
  CONSTRAINT program_position_options_program_id_fkey
    FOREIGN KEY (program_id) REFERENCES public.programs (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  CONSTRAINT program_position_options_label_not_blank
    CHECK (length(trim(label)) > 0),
  CONSTRAINT program_position_options_program_label_unique
    UNIQUE (program_id, label)
);

CREATE TABLE IF NOT EXISTS public.session_position_options (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL,
  label TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT session_position_options_pkey PRIMARY KEY (id),
  CONSTRAINT session_position_options_session_id_fkey
    FOREIGN KEY (session_id) REFERENCES public.sessions (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  CONSTRAINT session_position_options_label_not_blank
    CHECK (length(trim(label)) > 0),
  CONSTRAINT session_position_options_session_label_unique
    UNIQUE (session_id, label)
);

CREATE INDEX IF NOT EXISTS program_position_options_program_order_idx
  ON public.program_position_options (program_id, sort_order, label);

CREATE INDEX IF NOT EXISTS session_position_options_session_order_idx
  ON public.session_position_options (session_id, sort_order, label);

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
  COUNT(ci.id)                                      AS total_marked,
  COUNT(ci.id) FILTER (
    WHERE ci.position_label IS NOT NULL
      AND length(trim(ci.position_label)) > 0
  )                                                 AS positioned_count
FROM public.sessions s
JOIN public.programs p ON p.id = s.program_id
LEFT JOIN public.clock_ins ci ON ci.session_id = s.id
GROUP BY s.id, s.name, s.date, p.id, p.title, s.new_guest_count;
