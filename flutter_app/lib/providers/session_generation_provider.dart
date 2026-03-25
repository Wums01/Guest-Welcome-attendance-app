// lib/providers/session_generation_provider.dart
//
// Provider for triggering automatic session generation for Sunday/Wednesday services.
// This is useful for manual refreshes in case the scheduled job doesn't run.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_service.dart';

// FutureProvider for triggering auto-generation
// Usage: ref.refresh(autoGenerateWeeklySessionsProvider)
// Returns the number of sessions created
final autoGenerateWeeklySessionsProvider = FutureProvider<int>((ref) async {
  final sessionService = ref.read(sessionServiceProvider);
  return sessionService.triggerAutoGenerateWeeklySessions();
});
