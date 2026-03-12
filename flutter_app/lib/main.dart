import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/logger.dart';
import 'core/notifications.dart';
import 'providers/auth_provider.dart';

/// ---------------------------------------------------------------------------
/// Entry point
/// ---------------------------------------------------------------------------
/// Supabase credentials are injected at build time via --dart-define:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJxxx...
///
/// If either value is missing the app shows a clear config-error screen
/// instead of crashing with "No host specified".
/// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const tag = 'App';

  // AppConfig resolves credentials from --dart-define (run.sh / CI) with a
  // hardcoded dev fallback so "flutter run" from the IDE works without flags.
  const supabaseUrl = AppConfig.supabaseUrl;
  const supabaseKey = AppConfig.supabaseAnonKey;

  // Guard: if --dart-define values were not baked in, fail fast with a
  // human-readable screen rather than a cryptic "No host specified" crash.
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    AppLogger.error(
      tag,
      'SUPABASE_URL or SUPABASE_ANON_KEY not set. '
      'Run the app via run.sh or pass --dart-define flags.',
    );
    runApp(const _ConfigErrorApp());
    return;
  }

  AppLogger.info(tag, 'Initializing Supabase → $supabaseUrl');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  AppLogger.info(tag, 'Supabase ready');

  await NotificationService.init();

  // Bootstrap auth: restore persisted session before first frame.
  final container = ProviderContainer();
  await container.read(currentStaffProvider.notifier).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AttendanceApp(),
    ),
  );
}

/// Convenience getter — access the Supabase client anywhere without context.
/// Usage: supabase.from('members').select()
final supabase = Supabase.instance.client;

// ---------------------------------------------------------------------------
// Fallback screen shown when --dart-define credentials are missing.
// ---------------------------------------------------------------------------

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFBBF24), size: 64),
                SizedBox(height: 20),
                Text(
                  'Configuration Error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'SUPABASE_URL and SUPABASE_ANON_KEY were not\n'
                  'provided at build time.\n\n'
                  'Run the app with:\n'
                  '  bash flutter_app/run.sh',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
