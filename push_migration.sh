#!/bin/bash
# =============================================================================
# push_migration.sh — Apply the Supabase SQL migration
#
# Requires ONE of the following:
#
# Option A: Personal Access Token (PAT) — recommended
#   Get it from: Supabase Dashboard → Account Avatar → Access Tokens → Generate
#   Then run:
#     SUPABASE_ACCESS_TOKEN=sbp_xxxx bash push_migration.sh
#
# Option B: Database URL (direct postgres connection)
#   Get it from: Supabase Dashboard → Project Settings → Database → Connection string
#   Then run:
#     DB_URL="postgresql://postgres:[password]@db.xfornseashjnezqqjeun.supabase.co:5432/postgres"
#     bash push_migration.sh
#
# Option C: Supabase Dashboard SQL Editor (manual)
#   Copy-paste supabase/migrations/20260311000000_initial_schema.sql into the editor.

PROJECT_REF="xfornseashjnezqqjeun"

if [ -n "$DB_URL" ]; then
  echo "Pushing migration via direct DB URL..."
  npx supabase db push --db-url "$DB_URL"

elif [ -n "$SUPABASE_ACCESS_TOKEN" ]; then
  echo "Linking project and pushing migration..."
  npx supabase link --project-ref "$PROJECT_REF"
  npx supabase db push

else
  echo ""
  echo "ERROR: No credentials provided."
  echo ""
  echo "Run with one of:"
  echo "  SUPABASE_ACCESS_TOKEN=sbp_xxxx bash push_migration.sh"
  echo "  DB_URL='postgresql://postgres:...' bash push_migration.sh"
  echo ""
  echo "Or apply the migration manually in the Supabase SQL Editor:"
  echo "  https://supabase.com/dashboard/project/$PROJECT_REF/sql"
  echo ""
  exit 1
fi
