// lib/providers/auth_provider.dart
//
// Keeps track of the currently logged-in staff member.
// Persists across app restarts via SharedPreferences (AuthService).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/staff_user.dart';
import '../services/auth_service.dart';

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

  final AuthService _service;

  /// Called once on app start to restore a persisted session.
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final user = await _service.getCurrentUser();
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Mark a staff user as logged in and persist the session.
  Future<void> login(String staffId) async {
    await _service.saveSession(staffId);
    await _service.saveLastLogin(staffId); // record timestamp for 2-week check
    final user = await _service.getCurrentUser();
    state = AsyncValue.data(user);
  }

  /// Clear the session and set state to null.
  Future<void> logout() async {
    await _service.clearSession();
    state = const AsyncValue.data(null);
  }
}
