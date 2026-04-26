import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme/app_theme.dart';
import 'core/notifications.dart';
import 'core/utils/date_utils.dart';
import 'providers/session_generation_provider.dart';
import 'providers/theme_provider.dart';
import 'router.dart';
import 'services/fcm_service.dart';
import 'services/session_service.dart';

/// Root application widget.
/// Owns the GoRouter instance and the global MaterialTheme.
/// Uses the brightnessProvider to support light/dark mode.
///
/// Also acts as an AppLifecycleObserver: whenever the app is brought back to
/// the foreground on a Sunday or Wednesday, it re-triggers session generation
/// (in case the app was backgrounded across midnight and the cold-start fallback
/// already ran on a non-service day).
class AttendanceApp extends ConsumerStatefulWidget {
  const AttendanceApp({super.key});

  @override
  ConsumerState<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends ConsumerState<AttendanceApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final weekday = nowInLagos().weekday;
    if (weekday != DateTime.sunday && weekday != DateTime.wednesday) return;

    // Fire-and-forget: re-run generation when coming back to foreground on a
    // service day.  If new sessions are created, bump the signal so any screen
    // currently showing an empty list refreshes automatically.
    ref.read(sessionServiceProvider).triggerAutoGenerateWeeklySessions().then(
      (count) {
        if (count > 0) {
          ref.read(sessionRefreshSignalProvider.notifier).state++;
          NotificationService.showWeeklySessionGenerationNotification(count);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    FcmService.setRouter(router);
    final brightness = ref.watch(brightnessProvider);

    return MaterialApp.router(
      title: 'Guest Welcome Attendance',
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      routerConfig: router,
    );
  }
}
