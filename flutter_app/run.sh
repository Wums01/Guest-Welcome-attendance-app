#!/bin/bash
# =============================================================================
# flutter_app/run.sh
#
# Runs the Flutter app with Supabase credentials injected via --dart-define.
# Replace SUPABASE_ANON_KEY with the actual anon/public key from:
#   Supabase Dashboard → Project Settings → API → anon / public key
#
# Usage:
#   bash run.sh
#   bash run.sh --release
# =============================================================================

SUPABASE_URL="https://xfornseashjnezqqjeun.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhmb3Juc2Vhc2hqbmV6cXFqZXVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMjEyNjksImV4cCI6MjA4ODc5NzI2OX0.vL_4I6V4WDxnu1IhPUNB4J8idwr9c4LbpNs0hMSJAQo"

flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  "$@"
