// lib/providers/offline_provider.dart
//
// Riverpod providers for offline state and sync management.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/offline_sync_service.dart';

/// Stream of connectivity status (true = online, false = offline)
final isOnlineProvider = StreamProvider<bool>((ref) {
  return onConnectivityChanged();
});

/// Current offline status (true = offline)
final isOfflineProvider = StreamProvider<bool>((ref) {
  return onConnectivityChanged().map((isOnline) => !isOnline);
});

/// Get count of pending sync items
final pendingClockInsCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(offlineSyncServiceProvider);
  final pending = await service.getPendingClockIns();
  return pending.length;
});
