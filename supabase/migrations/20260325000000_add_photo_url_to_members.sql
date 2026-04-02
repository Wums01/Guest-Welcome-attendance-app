-- Add photo_url column to members table for member photos feature
-- This allows team leads to upload and manage member profile photos

ALTER TABLE public.members
ADD COLUMN photo_url TEXT;

-- Create index for potential future queries on photo_url
CREATE INDEX members_photo_url_idx
  ON public.members (photo_url);
