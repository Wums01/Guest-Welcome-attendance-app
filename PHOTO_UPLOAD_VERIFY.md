# Photo Upload Verification Checklist

## Critical Issues to Verify

### 1. **Database Schema** ✓ REQUIRED
- [ ] Migration `20260325000000_add_photo_url_to_members.sql` was applied
  - Command: `supabase db push`
  - Verify: `SELECT * FROM information_schema.columns WHERE table_name='members' AND column_name='photo_url';`

### 2. **Supabase Storage Bucket** ⚠️ CRITICAL
**Must exist before photos can upload!**

The `member-photos` bucket must be created with public access.

**Check if bucket exists:**
```bash
supabase storage list-buckets
```

**If NOT EXISTS, CREATE it:**
```sql
-- Run in Supabase SQL Editor
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('member-photos', 'member-photos', true, 52428800); -- 50MB limit

-- Allow anonymous users to view photos (RLS policy)
CREATE POLICY "Allow public read access"
ON storage.objects FOR SELECT
USING (bucket_id = 'member-photos');

-- Allow authenticated users to upload
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
USING (auth.role() = 'authenticated' AND bucket_id = 'member-photos');
```

### 3. **Flutter Code Upload Path** ✓ VERIFIED
Location: `flutter_app/lib/services/image_storage_service.dart`
- ✓ Uploads to `member-photos` bucket
- ✓ Path: `members/member-{id}-{timestamp}.jpg`
- ✓ Gets public URL after upload
- ✓ Error handling with AppLogger

### 4. **Member Update Flow** ✓ VERIFIED
Location: `flutter_app/lib/features/members/member_detail_screen.dart`

**Upload happens in `_save()` method (lines 720-752):**
```dart
// 1. Photo selected? Upload it first
if (_photoFile != null) {
  photoUrl = await ref.read(imageStorageServiceProvider)
      .uploadMemberPhoto(...)
}

// 2. Update member with photoUrl
await ref.read(memberServiceProvider).updateMember(
  widget.member.id,
  photoUrl: photoUrl,
)
```

### 5. **Display in UI** ✓ VERIFIED  
- Members list: Uses `MemberAvatar(imageUrl: member.photoUrl)`
- Member detail: Uses `MemberAvatar(imageUrl: member.photoUrl, radius: 36)`
- Session attendance: Uses `MemberAvatar(imageUrl: member?.photoUrl)`

---

## Testing Steps

### Step 1: Verify Database Column Exists
```bash
cd /Users/user/Desktop/bobby/Guest-Welcome-attendance-app
supabase db pull  # Pull latest schema
grep -r "photo_url" supabase/migrations/
```

### Step 2: Verify Storage Bucket Exists
Open Supabase Dashboard → Storage → Check if `member-photos` bucket exists
- If missing, create it via SQL (see section 2 above)

### Step 3: Test Upload on Flutter
1. Run app: `flutter run -d chrome`
2. Go to Members → Select a member → Edit
3. Click "Add Photo" button
4. Select a photo
5. Click "Save Changes"
6. Check browser console for errors (F12)
7. Check Supabase Storage → member-photos bucket for new file
8. Check Supabase Database → members table → photo_url column for URL

### Step 4: Debug Logs
If upload fails, check Flutter output for AppLogger messages:
- Search for: `ImageStorageService`
- Look for: "Uploading photo", "Photo uploaded", "Failed to upload"

---

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| Photos not showing in UI | `photo_url` not in database | Run: `supabase db push` |
| Files not in storage | Bucket doesn't exist | Create `member-photos` bucket in Supabase |
| Upload errors in logs | RLS policies missing | Add storage policies (see section 2) |
| Blank photo after edit | Save didn't wait for upload | Check if `_save()` actually awaits upload |
| Photos show initials instead | `photoUrl` is null in database | Verify column has data via Supabase UI |

---

## Database Query to Verify Data

Run this in Supabase SQL Editor:
```sql
SELECT id, full_name, photo_url 
FROM public.members 
WHERE photo_url IS NOT NULL 
LIMIT 10;
```

Should return members with non-null `photo_url` values like:
```
id                                    full_name      photo_url
12345678-1234-1234-1234-123456789012  John Doe       https://...member-photos/members/member-12345678-1234-1234-1234-123456789012-1711411234567.jpg
```

---

## Required Actions (DO THIS NOW)

1. **Verify migration ran:**
   ```bash
   supabase db push
   ```

2. **Create storage bucket if missing:**
   Open Supabase Dashboard → SQL Editor and run:
   ```sql
   INSERT INTO storage.buckets (id, name, public, file_size_limit)
   VALUES ('member-photos', 'member-photos', true, 52428800)
   ON CONFLICT (id) DO NOTHING;
   ```

3. **Test the flow:**
   - Edit a member
   - Upload a photo
   - Verify in Supabase Storage & Database
   - Refresh app and check if photo displays
