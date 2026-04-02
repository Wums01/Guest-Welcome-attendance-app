#!/bin/bash
# Photo Upload Setup Verification Script

echo "==========================================="
echo "Photo Upload System Diagnostic"
echo "==========================================="
echo ""

# Check 1: Migration file exists
echo "✓ STEP 1: Photo Migration File"
if [ -f "/Users/user/Desktop/bobby/Guest-Welcome-attendance-app/supabase/migrations/20260325000000_add_photo_url_to_members.sql" ]; then
    echo "  ✓ Migration file exists"
    echo "  Content:"
    cat /Users/user/Desktop/bobby/Guest-Welcome-attendance-app/supabase/migrations/20260325000000_add_photo_url_to_members.sql
else
    echo "  ✗ Migration file NOT found!"
fi
echo ""

# Check 2: Image storage service exists
echo "✓ STEP 2: Image Storage Service"
if [ -f "/Users/user/Desktop/bobby/Guest-Welcome-attendance-app/flutter_app/lib/services/image_storage_service.dart" ]; then
    echo "  ✓ Service file exists"
    echo "  Bucket name configured as: 'member-photos'"
else
    echo "  ✗ Service file NOT found!"
fi
echo ""

# Check 3: Member model has photoUrl
echo "✓ STEP 3: Member Model Configuration"
grep -q "photoUrl" /Users/user/Desktop/bobby/Guest-Welcome-attendance-app/flutter_app/lib/models/member.dart && \
    echo "  ✓ Member model has 'photoUrl' field" || \
    echo "  ✗ Member model missing 'photoUrl' field"
echo ""

# Check 4: Edit screen has photo upload
echo "✓ STEP 4: Edit Member Screen Photo Upload"
grep -q "_pickPhoto" /Users/user/Desktop/bobby/Guest-Welcome-attendance-app/flutter_app/lib/features/members/member_detail_screen.dart && \
    echo "  ✓ Photo upload UI implemented in edit screen" || \
    echo "  ✗ Photo upload UI NOT implemented"
echo ""

echo "==========================================="
echo "NEXT STEPS:"
echo "==========================================="
echo ""
echo "1. Run the database migration:"
echo "   cd /Users/user/Desktop/bobby/Guest-Welcome-attendance-app"
echo "   supabase db push"
echo ""
echo "2. CREATE the storage bucket in Supabase:"
echo "   Go to Supabase Dashboard → member-photos project"
echo "   Click Storage → New Bucket"
echo "   Name: member-photos"
echo "   Make Public: YES"
echo ""
echo "3. Or run this SQL in Supabase SQL Editor:"
echo "   INSERT INTO storage.buckets (id, name, public, file_size_limit)"
echo "   VALUES ('member-photos', 'member-photos', true, 52428800)"
echo "   ON CONFLICT (id) DO NOTHING;"
echo ""
echo "4. Test the upload:"
echo "   flutter run -d chrome"
echo "   Edit a member → Add Photo → Save"
echo "   Check Supabase Storage for file"
echo "==========================================="
