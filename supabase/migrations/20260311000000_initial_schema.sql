-- =============================================================================
-- Guest Welcome Attendance App — Supabase SQL Migration
-- Version  : 1.0.0
-- Date     : 2026-03-11
-- Author   : Generated from localStorage schema analysis
--
-- Entity relationships:
--   programs 1──< sessions 1──< clock_ins >──1 members
--
-- Business rules enforced here (not just in app code):
--   1.  offline_code  is exactly 6 numeric digits and globally unique
--   2.  birthday_md / anniversary_md must be "MM-DD" format
--   3.  anniversary_md may only be set when is_married = TRUE
--   4.  Program non-TBD: start_date IS NOT NULL; end_date >= start_date
--   5.  Session: end_time > start_time when both are set
--   6.  One clock_in record per (session_id, member_id) pair
--   7.  status = 'absent' cannot be set via method = 'offline_code'
--   8.  Clock-in status 'present' / 'excused' is immutable (trigger)
--   9.  Deleting a program cascades to its sessions
--   10. Deleting a session cascades to its clock_ins
--   11. Members with existing clock_ins cannot be deleted (RESTRICT)
-- =============================================================================


-- =============================================================================
-- SECTION 0: EXTENSIONS
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- required for gin_trgm_ops (fuzzy name search)


-- =============================================================================
-- SECTION 1: ENUM TYPES
-- =============================================================================

-- Church team assignment for members and service scoping
CREATE TYPE public.team AS ENUM (
  'Team A',
  'Team B',
  'Team C',
  'None'
);

-- Types of recurring or one-off programs
CREATE TYPE public.program_type AS ENUM (
  'sunday',       -- auto-creates 3 service sessions
  'wednesday',    -- auto-creates 1 "Switch Service" session
  'program',      -- manual sessions
  'meeting',      -- manual sessions
  'training'      -- manual sessions
);

-- Attendance outcome for a clock_in record
CREATE TYPE public.attendance_status AS ENUM (
  'present',    -- member attended
  'absent',     -- member did not attend (set only by finalize_absences, never via UI)
  'excused'     -- member was excused
);

-- How the attendance record was created
CREATE TYPE public.clock_in_method AS ENUM (
  'manual',         -- admin manually marked
  'qr',             -- QR code scan
  'self',           -- self-check-in
  'offline_code'    -- 6-digit numeric code entry
);


-- =============================================================================
-- SECTION 2: REUSABLE TRIGGER FUNCTION — auto-update updated_at
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


-- =============================================================================
-- SECTION 3: MEMBERS
-- =============================================================================
--
-- Represents a church unit member who can attend sessions.
-- Each member has a unique 6-digit offline_code used to mark attendance
-- without internet connectivity.
-- =============================================================================

CREATE TABLE public.members (
  id              UUID          NOT NULL DEFAULT gen_random_uuid(),
  full_name       TEXT          NOT NULL CHECK (char_length(full_name) > 0),
  phone           TEXT          NOT NULL DEFAULT '',
  offline_code    CHAR(6)       NOT NULL,
  team            public.team   NOT NULL DEFAULT 'None',
  is_married      BOOLEAN       NOT NULL DEFAULT FALSE,
  birthday_md     CHAR(5)       NOT NULL,         -- format: "MM-DD"
  anniversary_md  CHAR(5)       NULL,             -- format: "MM-DD", only for married members
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),

  -- ── Primary key ────────────────────────────────────────────────────────────
  CONSTRAINT members_pkey PRIMARY KEY (id),

  -- ── Offline code must be exactly 6 numeric digits ──────────────────────────
  CONSTRAINT members_offline_code_is_numeric
    CHECK (offline_code ~ '^\d{6}$'),

  -- ── Offline code must be globally unique (fast lookup during check-in) ──────
  CONSTRAINT members_offline_code_unique
    UNIQUE (offline_code),

  -- ── Birthday format: MM-DD ──────────────────────────────────────────────────
  CONSTRAINT members_birthday_md_format
    CHECK (birthday_md ~ '^\d{2}-\d{2}$'),

  -- ── Anniversary format: MM-DD when provided ────────────────────────────────
  CONSTRAINT members_anniversary_md_format
    CHECK (anniversary_md IS NULL OR anniversary_md ~ '^\d{2}-\d{2}$'),

  -- ── Anniversary only makes sense for married members ───────────────────────
  CONSTRAINT members_anniversary_requires_married
    CHECK (is_married = TRUE OR anniversary_md IS NULL)
);

-- Indexes
CREATE INDEX members_team_idx
  ON public.members (team);                                   -- team-scoped queries

CREATE INDEX members_offline_code_idx
  ON public.members (offline_code);                           -- check-in code lookup

CREATE INDEX members_birthday_md_idx
  ON public.members (birthday_md);                            -- Home page celebrations

CREATE INDEX members_full_name_trgm_idx
  ON public.members USING gin (full_name gin_trgm_ops);       -- fuzzy name search (requires pg_trgm)

-- updated_at trigger
CREATE TRIGGER members_set_updated_at
  BEFORE UPDATE ON public.members
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- SECTION 4: PROGRAMS
-- =============================================================================
--
-- A recurring or one-off church program. Sunday and Wednesday programs
-- automatically create sessions. All others require manual session creation.
--
-- team_scope controls which members are expected to attend:
--   'all'              → all members
--   'Team A/B/C/None'  → only that team
--   NULL               → no team restriction defined
-- =============================================================================

CREATE TABLE public.programs (
  id            UUID                NOT NULL DEFAULT gen_random_uuid(),
  title         TEXT                NOT NULL CHECK (char_length(title) > 0),
  program_type  public.program_type NOT NULL,
  is_tbd        BOOLEAN             NOT NULL DEFAULT FALSE,
  start_date    DATE                NULL,   -- NULL when is_tbd = TRUE
  end_date      DATE                NULL,   -- NULL when is_tbd = TRUE
  -- TEXT instead of enum because valid values are 'all' | Team | NULL
  -- and 'all' is not a member of the team enum
  team_scope    TEXT                NULL,
  created_at    TIMESTAMPTZ         NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ         NOT NULL DEFAULT now(),

  -- ── Primary key ────────────────────────────────────────────────────────────
  CONSTRAINT programs_pkey PRIMARY KEY (id),

  -- ── Non-TBD programs must have a start date ────────────────────────────────
  CONSTRAINT programs_start_date_required_when_dated
    CHECK (is_tbd = TRUE OR start_date IS NOT NULL),

  -- ── end_date must not precede start_date ───────────────────────────────────
  CONSTRAINT programs_end_date_gte_start_date
    CHECK (
      start_date IS NULL
      OR end_date IS NULL
      OR end_date >= start_date
    ),

  -- ── TBD programs must have null dates ──────────────────────────────────────
  CONSTRAINT programs_tbd_dates_null
    CHECK (
      is_tbd = FALSE
      OR (start_date IS NULL AND end_date IS NULL)
    ),

  -- ── team_scope restricted to known values ──────────────────────────────────
  CONSTRAINT programs_team_scope_valid
    CHECK (
      team_scope IS NULL
      OR team_scope IN ('all', 'Team A', 'Team B', 'Team C', 'None')
    )
);

-- Indexes
CREATE INDEX programs_program_type_idx ON public.programs (program_type);
CREATE INDEX programs_start_date_idx   ON public.programs (start_date);
CREATE INDEX programs_team_scope_idx   ON public.programs (team_scope);

-- updated_at trigger
CREATE TRIGGER programs_set_updated_at
  BEFORE UPDATE ON public.programs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- SECTION 5: SESSIONS
-- =============================================================================
--
-- A single occurrence of a program (one service, one meeting slot, etc.).
-- Sunday programs produce 3 sessions per date:
--   "Service 1" → expected team: Team A  (opens 06:30 Lagos)
--   "Service 2" → expected team: Team B  (opens 08:30 Lagos)
--   "Service 3" → expected team: Team C  (opens 11:00 Lagos)
-- Wednesday programs produce 1 session: "Switch Service"
-- =============================================================================

CREATE TABLE public.sessions (
  id                UUID        NOT NULL DEFAULT gen_random_uuid(),
  program_id        UUID        NOT NULL,
  name              TEXT        NOT NULL CHECK (char_length(name) > 0),
  date              DATE        NOT NULL,
  start_time        TIME        NULL,
  end_time          TIME        NULL,
  clock_in_required BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- ── Primary key ────────────────────────────────────────────────────────────
  CONSTRAINT sessions_pkey PRIMARY KEY (id),

  -- ── Foreign key → programs (CASCADE: deleting program removes its sessions) ─
  CONSTRAINT sessions_program_id_fkey
    FOREIGN KEY (program_id) REFERENCES public.programs (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  -- ── end_time must be after start_time when both are provided ───────────────
  CONSTRAINT sessions_end_time_after_start_time
    CHECK (
      start_time IS NULL
      OR end_time IS NULL
      OR end_time > start_time
    )
);

-- Indexes
CREATE INDEX sessions_program_id_idx ON public.sessions (program_id);  -- FK lookup + program sessions list
CREATE INDEX sessions_date_idx       ON public.sessions (date);         -- date-based session browsing
CREATE INDEX sessions_date_name_idx  ON public.sessions (date, name);   -- timing gate name matching


-- updated_at trigger
CREATE TRIGGER sessions_set_updated_at
  BEFORE UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- SECTION 6: CLOCK_INS  (Attendance Records)
-- =============================================================================
--
-- One record per (session, member) pair.
-- Status lifecycle:
--   absent  ──can be upgraded──▶  present  (immutable)
--   absent  ──can be upgraded──▶  excused  (immutable)
--   present ──────────────────▶  LOCKED (trigger rejects further updates)
--   excused ──────────────────▶  LOCKED (trigger rejects further updates)
--
-- 'absent' is NEVER set through the UI or offline_code path.
-- It is only written by finalize_session_absences() (batch operation).
-- =============================================================================

CREATE TABLE public.clock_ins (
  id          UUID                      NOT NULL DEFAULT gen_random_uuid(),
  session_id  UUID                      NOT NULL,
  member_id   UUID                      NOT NULL,
  status      public.attendance_status  NOT NULL,
  method      public.clock_in_method    NOT NULL,
  clocked_at  TIMESTAMPTZ               NOT NULL DEFAULT now(),
  -- Note: no created_at / updated_at — clocked_at IS the canonical timestamp.
  -- An absent→present upgrade overwrites clocked_at to reflect time of actual arrival.

  -- ── Primary key ────────────────────────────────────────────────────────────
  CONSTRAINT clock_ins_pkey PRIMARY KEY (id),

  -- ── Foreign key → sessions (CASCADE: deleting session removes its records) ─
  CONSTRAINT clock_ins_session_id_fkey
    FOREIGN KEY (session_id) REFERENCES public.sessions (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  -- ── Foreign key → members (RESTRICT: preserve attendance history) ──────────
  -- Members with attendance records cannot be deleted.
  -- Delete clock_ins first if you need to remove a member.
  CONSTRAINT clock_ins_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES public.members (id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  -- ── Uniqueness: one attendance record per member per session ───────────────
  CONSTRAINT clock_ins_member_session_unique
    UNIQUE (session_id, member_id),

  -- ── 'absent' cannot be set via offline_code (clockInByOfflineCode rule) ────
  CONSTRAINT clock_ins_absent_not_via_offline_code
    CHECK (
      NOT (status = 'absent' AND method = 'offline_code')
    )
);

-- Indexes
CREATE INDEX clock_ins_session_id_idx
  ON public.clock_ins (session_id);                           -- attendance list per session

CREATE INDEX clock_ins_member_id_idx
  ON public.clock_ins (member_id);                            -- attendance history per member

CREATE INDEX clock_ins_status_idx
  ON public.clock_ins (status);                               -- filter by present/absent/excused

CREATE INDEX clock_ins_clocked_at_idx
  ON public.clock_ins (clocked_at);                           -- time-range report queries

CREATE INDEX clock_ins_session_status_idx
  ON public.clock_ins (session_id, status);                   -- count present/absent per session


-- =============================================================================
-- SECTION 7: TRIGGER — Enforce clock_in status immutability
-- =============================================================================
--
-- Once a clock_in reaches status 'present' or 'excused' it must never be
-- changed to any other status. This mirrors the app rule:
--   if (existing.status === "present" || existing.status === "excused")
--     throw new Error("Already marked")
-- =============================================================================

CREATE OR REPLACE FUNCTION public.prevent_clock_in_status_downgrade()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Block any status change away from a terminal status
  IF OLD.status IN ('present', 'excused') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION
      'Cannot change clock_in status from ''%'' to ''%'': status is immutable once set to present or excused.',
      OLD.status, NEW.status;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER clock_ins_prevent_status_downgrade
  BEFORE UPDATE OF status ON public.clock_ins
  FOR EACH ROW EXECUTE FUNCTION public.prevent_clock_in_status_downgrade();


-- =============================================================================
-- SECTION 8: SETTINGS
-- =============================================================================
--
-- Simple key-value store for app-wide flags.
-- Current keys:
--   test_mode_enabled  →  'true' | 'false'
--     When true, bypasses the Lagos-time service timing gate on the check-in page.
-- =============================================================================

CREATE TABLE public.settings (
  key        TEXT        NOT NULL,
  value      TEXT        NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT settings_pkey PRIMARY KEY (key)
);

-- Seed with default values
INSERT INTO public.settings (key, value) VALUES
  ('test_mode_enabled', 'false');

-- updated_at trigger
CREATE TRIGGER settings_set_updated_at
  BEFORE UPDATE ON public.settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- SECTION 9: ROW LEVEL SECURITY (RLS)
-- =============================================================================
--
-- RLS is enabled on all tables. Default posture: deny all.
-- Policies below grant full access to authenticated users.
-- Tighten per-role (admin vs member) when auth roles are introduced.
-- =============================================================================

ALTER TABLE public.members   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.programs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clock_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings  ENABLE ROW LEVEL SECURITY;

-- Authenticated users (admins/leaders) have full CRUD on all tables
CREATE POLICY "authenticated_full_access" ON public.members
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "authenticated_full_access" ON public.programs
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "authenticated_full_access" ON public.sessions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "authenticated_full_access" ON public.clock_ins
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "authenticated_full_access" ON public.settings
  FOR ALL TO authenticated USING (true) WITH CHECK (true);


-- =============================================================================
-- SECTION 10: HELPFUL VIEWS
-- =============================================================================

-- Session attendance summary (present / absent / excused count per session)
CREATE VIEW public.session_attendance_summary AS
SELECT
  s.id                                          AS session_id,
  s.name                                        AS session_name,
  s.date                                        AS session_date,
  p.id                                          AS program_id,
  p.title                                       AS program_title,
  COUNT(*) FILTER (WHERE ci.status = 'present') AS present_count,
  COUNT(*) FILTER (WHERE ci.status = 'absent')  AS absent_count,
  COUNT(*) FILTER (WHERE ci.status = 'excused') AS excused_count,
  COUNT(*)                                      AS total_marked
FROM public.sessions s
JOIN public.programs p ON p.id = s.program_id
LEFT JOIN public.clock_ins ci ON ci.session_id = s.id
GROUP BY s.id, s.name, s.date, p.id, p.title;


-- Monthly leaderboard (present count per member per YYYY-MM)
CREATE VIEW public.monthly_leaderboard AS
SELECT
  to_char(s.date, 'YYYY-MM')  AS year_month,
  m.id                         AS member_id,
  m.full_name,
  m.team,
  m.offline_code,
  COUNT(*)                     AS present_count
FROM public.clock_ins ci
JOIN public.members  m ON m.id = ci.member_id
JOIN public.sessions s ON s.id = ci.session_id
WHERE ci.status = 'present'
GROUP BY to_char(s.date, 'YYYY-MM'), m.id, m.full_name, m.team, m.offline_code;


-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
