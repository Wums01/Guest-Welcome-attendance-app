-- Staff users: team leads and assistants who operate the attendance app
-- Uses pgcrypto bcrypt for passwords — no Supabase Auth required.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE public.staff_role AS ENUM ('team_lead', 'assistant');

CREATE TABLE public.staff_users (
  id            UUID              NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  full_name     TEXT              NOT NULL CHECK (char_length(full_name) > 0),
  team          public.team       NOT NULL DEFAULT 'None',
  role          public.staff_role NOT NULL DEFAULT 'assistant',
  avatar_url    TEXT,
  password_hash TEXT,   -- NULL means first login; password has not been set yet
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER staff_users_set_updated_at
  BEFORE UPDATE ON public.staff_users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.staff_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_full_access" ON public.staff_users
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- Set (or replace) password for a given staff user.
CREATE OR REPLACE FUNCTION public.set_staff_password(p_staff_id UUID, p_password TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.staff_users
     SET password_hash = crypt(p_password, gen_salt('bf', 12)),
         updated_at    = now()
   WHERE id = p_staff_id;
END;
$$;

-- Verify a plain-text password against the stored bcrypt hash.
-- Returns FALSE if the user has no password set yet.
CREATE OR REPLACE FUNCTION public.check_staff_password(p_staff_id UUID, p_password TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_hash TEXT;
BEGIN
  SELECT password_hash INTO v_hash
    FROM public.staff_users
   WHERE id = p_staff_id;
  IF v_hash IS NULL THEN
    RETURN FALSE;
  END IF;
  RETURN crypt(p_password, v_hash) = v_hash;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_staff_password  TO anon;
GRANT EXECUTE ON FUNCTION public.check_staff_password TO anon;
