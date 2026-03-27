# Photo Upload Testing Guide - Step by Step

## Prerequisites ✅
- [x] Code reviewed and verified
- [x] Enhanced logging added
- [x] No build errors (`flutter analyze` passes)

---

## STEP 1: Ensure Database is Ready

**Run migration to add photo_url column:**
```bash
cd /Users/user/Desktop/bobby/Guest-Welcome-attendance-app
supabase db push
```

**Verify photo_url column exists** in Supabase:
1. Open: https://supabase.com → member-photos project → SQL Editor
2. Run this query:
```sql
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'members' AND column_name = 'photo_url';
```
✅ Should return: `photo_url | text`

---

## STEP 2: Ensure Storage Bucket Exists

**Check if bucket exists** in Supabase Dashboard:
1. Go to: https://supabase.com → member-photos project → Storage
2. Look for bucket named: `member-photos`

**If it DOES NOT exist, CREATE it immediately:**

Option A - Via Dashboard:
1. Click "New Bucket"
2. Name: `member-photos`
3. Make Public: ✓ YES
4. Click Create

Option B - Via SQL (copy-paste into SQL Editor):
```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('member-photos', 'member-photos', true, 52428800)
ON CONFLICT (id) DO NOTHING;
```

**If RLS policies missing, run this SQL:**
```sql
-- Allow anyone to view public files
CREATE POLICY "Allow public read access"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'member-photos');

-- Allow authenticated uploads
CREATE POLICY "Allow authenticated uploads"  
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'member-photos');
```

✅ Verify bucket is PUBLIC (not private)

---

## STEP 3: Test Upload in Flutter App

**Terminal 1 - Start Flutter app:**
```bash
cd /Users/user/Desktop/bobby/Guest-Welcome-attendance-app/flutter_app
flutter run -d chrome
```

**Terminal 2 - Watch the logs:**
Keep the first terminal open to see all logs

**In the app:**
1. Navigate to: Members → [Click any member]
2. Click: Edit (pencil icon)
3. Click: "Add Photo" button
4. Select a photo from your computer
5. Click: "Save Changes"

**Watch for these log messages:**
```
📸 UPLOAD START: member=..., file=..., size=... bytes
📤 Uploading to bucket: member-photos, path: members/member-...
✓ File uploaded successfully to: members/member-...
✓ PUBLIC URL: https://...
💾 SAVING MEMBER: ...
📝 Updating member fields: ...
✓ Member updated successfully!
```

---

## STEP 4: Verify in Supabase

### Check Photo File Uploaded
1. Go to: Supabase Dashboard → Storage
2. Click: `member-photos` bucket
3. Navigate into: `members/` folder
4. **Should see a new file:** `member-{uuid}-{timestamp}.jpg`
5. Click the file → it should display the image

❌ **If NO file appears:**
- Issue: Storage bucket doesn't exist or RLS is blocking uploads
- Fix: Go back to STEP 2, create bucket & policies

### Check Database Updated
1. Go to: Supabase Dashboard → SQL Editor
2. Run this query:
```sql
SELECT id, full_name, photo_url 
FROM public.members 
WHERE photo_url IS NOT NULL 
ORDER BY updated_at DESC 
LIMIT 5;
```

✅ **Should see:**
```
id                                    full_name      photo_url
12345678-...                          John Doe       https://..../member-photos/members/member-...jpg
```

❌ **If photo_url is NULL:**
- Issue: Update query didn't save the URL
- Fix: Check Flutter logs for errors (scroll up in terminal)

---

## STEP 5: Verify in App UI

**Refresh the app or go back to Members list:**
1. Close the edit sheet
2. Go back to Members
3. The member card should now show **their photo** instead of initials
4. Click on member again → Profile should show large photo

❌ **If still showing initials:**
- Issue: UI isn't reading `photo_url` from database
- Fix: Pull fresh data - navigate away & back, or do a hot restart

```bash
# In Flutter app, press:
r  # hot reload
R  # hot restart (better)
```

---

## STEP 6: Troubleshooting

### Issue: "❌ UPLOAD FAILED" in logs

**Check these in order:**

1. **Is bucket public?**
   ```bash
   # In SQL Editor
   SELECT id, name, public FROM storage.buckets WHERE id = 'member-photos';
   ```
   Must show: `public = true`

2. **Is RLS policy correct?**
   ```bash
   SELECT * FROM pg_policies WHERE schemaname = 'storage';
   ```
   Look for policy names containing `member-photos`

3. **Is user authenticated?**
   Check: Supabase → Authentication → Users
   Verify your current user is listed

### Issue: Database column doesn't exist

```bash
# In SQL Editor, check:
SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'members';
```

If `photo_url` not in list:
```bash
# Run migration
supabase db push
```

### Issue: Data saved but photos don't show in list

1. Pull latest data:
   ```dart
   ref.invalidate(membersListProvider);  // Force refresh
   ```

2. Check Member model has photoUrl:
   ```dart
   // Should be in Member class
   final String? photoUrl;
   ```

3. Check avatar widget uses it:
   ```dart
   MemberAvatar(
     fullName: member.fullName,
     imageUrl: member.photoUrl,  // THIS MUST BE HERE
     radius: 22,
   )
   ```

---

## Final Verification Checklist

- [ ] Migration ran: `photo_url` column exists in `members` table
- [ ] Storage bucket exists: `member-photos` is PUBLIC
- [ ] Upload logs show success messages with URLs
- [ ] File appears in Supabase Storage → member-photos/members/
- [ ] Photo URL saved in database (photo_url column has value)
- [ ] App refreshes and shows photo instead of initials
- [ ] Photo appears in: Members list, member profile, session attendance

---

## Quick Commands Reference

```bash
# View detailed logs
cd flutter_app && flutter run -d chrome 2>&1 | grep -E "(📸|📤|✓|❌)"

# Restart database
supabase db push

# Check what's in the bucket
# (Via Dashboard → Storage → member-photos/members/)

# Query members with photos
# (Via Dashboard → SQL Editor - see STEP 4)
```

---

## Need More Help?

1. **Check browser console** (F12 → Console) for JavaScript errors
2. **Check Flutter logs** - look for "ImageStorageService" and "EditMemberSheet" tags
3. **Check Supabase dashboard** - verify bucket exists and is public
4. **Run migrations** - `supabase db push` to ensure schema is up to date
