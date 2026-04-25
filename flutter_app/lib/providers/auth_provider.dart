// lib/providers/auth_provider.dart
//
// Keeps track of the currently logged-in staff member.
// Persists across app restarts via SharedPreferences (AuthService).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger.dart';
import '../models/staff_user.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final currentStaffProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<StaffUser?>>(
  (ref) => AuthNotifier(ref.read(authServiceProvider)),
);

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AuthNotifier extends StateNotifier<AsyncValue<StaffUser?>> {
  AuthNotifier(this._service) : super(const AsyncValue.loading());

  static const _tag = 'AuthNotifier';
  final AuthService _service;

  /// Called once on app start to restore a persisted session.
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final user = await _service.getCurrentUser();
      state = AsyncValue.data(user);
      if (user != null) {
        AppLogger.info(_tag, 'Restored session for staffId=${user.id}; initializing FCM');
        await FcmService.initialize(user.id);
      } else {
        AppLogger.info(_tag, 'No persisted session found');
      }
    } catch (e, st) {
      AppLogger.error(_tag, 'load failed', e, st);
      state = AsyncValue.error(e, st);
    }
  }

  /// Mark a staff user as logged in and persist the session.
  Future<void> login(String staffId) async {
    AppLogger.info(_tag, 'Login started for staffId=$staffId');
    await _service.saveSession(staffId);
    await _service.saveLastLogin(staffId); // record timestamp for 2-week check
    final user = await _service.getCurrentUser();
    state = AsyncValue.data(user);
    // Register FCM token for this device so push notifications are delivered.
    AppLogger.info(_tag, 'Login resolved current user; initializing FCM for staffId=$staffId');
    await FcmService.initialize(staffId);
  }

  /// Clear the session and set state to null.
  Future<void> logout() async {
    AppLogger.info(_tag, 'Logout started');
    await FcmService.deleteToken();
    await _service.clearSession();
    state = const AsyncValue.data(null);
  }

  /// Re-fetch the current user from DB and update state.
  /// Call after updating avatar or full name to propagate changes app-wide.
  Future<void> refreshCurrentUser() async {
    try {
      final user = await _service.getCurrentUser();
      state = AsyncValue.data(user);
    } catch (e, st) {
      AppLogger.error(_tag, 'refreshCurrentUser failed', e, st);
      state = AsyncValue.error(e, st);
    }
  }
}
