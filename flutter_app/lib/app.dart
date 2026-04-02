import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'router.dart';

/// Root application widget.
/// Owns the GoRouter instance and the global MaterialTheme.
/// Uses the brightnessProvider to support light/dark mode.
class AttendanceApp extends ConsumerWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
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
