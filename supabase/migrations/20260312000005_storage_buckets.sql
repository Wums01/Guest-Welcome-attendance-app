-- supabase/migrations/20260312000005_storage_buckets.sql
--
-- Creates the staff-avatars storage bucket used by StaffProfileScreen.
-- Bucket is public (URLs are readable without auth — safe for avatar images).
-- Write access requires a valid anon/service role key (our app uses anon key).

-- Create bucket (idempotent)
INSERT INTO storage.buckets (id, name, public)
VALUES ('staff-avatars', 'staff-avatars', true)
ON CONFLICT (id) DO NOTHING;

-- Allow anyone to view avatars (public bucket)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'staff_avatars_public_read'
  ) THEN
    CREATE POLICY staff_avatars_public_read
      ON storage.objects FOR SELECT
      TO public
      USING (bucket_id = 'staff-avatars');
  END IF;
END $$;

-- Allow anon role to upload / update / delete (app uses anon key)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'staff_avatars_anon_insert'
  ) THEN
    CREATE POLICY staff_avatars_anon_insert
      ON storage.objects FOR INSERT
      TO anon
      WITH CHECK (bucket_id = 'staff-avatars');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'staff_avatars_anon_update'
  ) THEN
    CREATE POLICY staff_avatars_anon_update
      ON storage.objects FOR UPDATE
      TO anon
      USING (bucket_id = 'staff-avatars');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'staff_avatars_anon_delete'
  ) THEN
    CREATE POLICY staff_avatars_anon_delete
      ON storage.objects FOR DELETE
      TO anon
      USING (bucket_id = 'staff-avatars');
  END IF;
END $$;
