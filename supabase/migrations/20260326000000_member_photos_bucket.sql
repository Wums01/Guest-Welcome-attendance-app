-- supabase/migrations/20260326000000_member_photos_bucket.sql
--
-- Creates the member-photos storage bucket for member profile photos.
-- Bucket is public (URLs are readable without auth).
-- Write access requires a valid anon key.

-- Create bucket (idempotent)
INSERT INTO storage.buckets (id, name, public)
VALUES ('member-photos', 'member-photos', true)
ON CONFLICT (id) DO NOTHING;

-- Allow anyone to view member photos (public bucket)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'member_photos_public_read'
  ) THEN
    CREATE POLICY member_photos_public_read
      ON storage.objects FOR SELECT
      TO public
      USING (bucket_id = 'member-photos');
  END IF;
END $$;

-- Allow anon role to upload / update (app uses anon key)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'member_photos_anon_insert'
  ) THEN
    CREATE POLICY member_photos_anon_insert
      ON storage.objects FOR INSERT
      TO anon
      WITH CHECK (bucket_id = 'member-photos');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'member_photos_anon_update'
  ) THEN
    CREATE POLICY member_photos_anon_update
      ON storage.objects FOR UPDATE
      TO anon
      USING (bucket_id = 'member-photos');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'member_photos_anon_delete'
  ) THEN
    CREATE POLICY member_photos_anon_delete
      ON storage.objects FOR DELETE
      TO anon
      USING (bucket_id = 'member-photos');
  END IF;
END $$;
