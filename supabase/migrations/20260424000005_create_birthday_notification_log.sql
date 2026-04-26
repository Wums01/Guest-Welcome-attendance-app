-- supabase/migrations/20260424000005_create_birthday_notification_log.sql
-- Prevents duplicate birthday/anniversary push notifications.

CREATE TABLE IF NOT EXISTS public.birthday_notification_log (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id         UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL CHECK (
    notification_type IN (
      'birthday_eve', 'birthday_morning',
      'anniversary_eve', 'anniversary_morning'
    )
  ),
  sent_at           TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  year              INT NOT NULL,
  UNIQUE (member_id, notification_type, year)
);

ALTER TABLE public.birthday_notification_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY birthday_log_authenticated
  ON public.birthday_notification_log FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY birthday_log_anon
  ON public.birthday_notification_log FOR ALL TO anon
  USING (true) WITH CHECK (true);
