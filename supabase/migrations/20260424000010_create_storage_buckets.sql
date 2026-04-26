-- Create storage buckets for member photos and staff avatars

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('member-photos', 'member-photos', true, 5242880, ARRAY['image/jpeg','image/png','image/webp']),
  ('staff-avatars', 'staff-avatars', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload to member-photos
CREATE POLICY "Authenticated upload member photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'member-photos');

CREATE POLICY "Public read member photos"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'member-photos');

CREATE POLICY "Authenticated delete member photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'member-photos');

-- Allow authenticated users to upload to staff-avatars
CREATE POLICY "Authenticated upload staff avatars"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'staff-avatars');

CREATE POLICY "Public read staff avatars"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'staff-avatars');

CREATE POLICY "Authenticated delete staff avatars"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'staff-avatars');
