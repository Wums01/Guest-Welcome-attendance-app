// lib/core/config.dart
//
// Supabase credentials resolved at compile time.
//
// Priority order:
//   1. --dart-define flags (set by run.sh / CI — always wins in production)
//   2. Hardcoded dev fallbacks below (allows "flutter run" from IDE without flags)
//
// Security note:
//   The anon key is intentionally public — it only grants anonymous access and
//   is protected by Row Level Security (RLS) in Supabase.
//   The service_role key is NEVER stored here.

class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xfornseashjnezqqjeun.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
        '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhmb3Juc2Vhc2hqbmV6cXFqZXVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMjEyNjksImV4cCI6MjA4ODc5NzI2OX0'
        '.vL_4I6V4WDxnu1IhPUNB4J8idwr9c4LbpNs0hMSJAQo',
  );
}
