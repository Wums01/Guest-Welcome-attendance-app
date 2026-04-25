// lib/services/auth_service.dart
//
// Custom staff authentication backed by Supabase pgcrypto RPCs.
// No Supabase Auth is involved; session is stored in SharedPreferences.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/staff_user.dart';
import '../models/enums.dart';
import '../core/logger.dart';

const _tag = 'AuthService';
const _sessionKey = 'staff_session_id';
const _lastLoginPrefix = 'last_login_';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(Supabase.instance.client),
);

class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  // -------------------------------------------------------------------------
  // Staff CRUD
  // -------------------------------------------------------------------------

  Future<List<StaffUser>> getStaffUsers() async {
    AppLogger.info(_tag, 'Fetching all staff users');
    try {
      final data = await _client
          .from('staff_users')
          .select('id, full_name, team, role, avatar_url, password_hash')
          .order('full_name');
      return (data as List).map((r) => StaffUser.fromJson(r)).toList();
    } catch (e, st) {
      AppLogger.error(_tag, 'Failed to fetch staff users', e, st);
      rethrow;
    }
  }

  Future<StaffUser> createStaffUser({
    required String fullName,
    required Team team,
    required StaffRole role,
  }) async {
    AppLogger.info(_tag, 'Creating staff user: $fullName');
    try {
      final rows = await _client
          .from('staff_users')
          .insert({
            'full_name': fullName,
            'team': team.value,
            'role': role.value,
          })
          .select('id, full_name, team, role, avatar_url, password_hash');
      return StaffUser.fromJson((rows as List).first);
    } catch (e, st) {
      AppLogger.error(_tag, 'Failed to create staff user', e, st);
      rethrow;
    }
  }

  Future<void> deleteStaffUser(String id, {StaffRole? callerRole}) async {
    AppLogger.info(_tag, 'Deleting staff user: $id');
    try {
      // Fetch target role to enforce permission rules
      final row = await _client
          .from('staff_users')
          .select('role')
          .eq('id', id)
          .single();
      final targetRole = StaffRole.fromValue(row['role'] as String);
      if (callerRole == StaffRole.assistant &&
          targetRole == StaffRole.teamLead) {
        throw Exception('Assistants cannot delete team leads.');
      }
      await _client.from('staff_users').delete().eq('id', id);
    } catch (e, st) {
      AppLogger.error(_tag, 'Failed to delete staff user', e, st);
      rethrow;
    }
  }

  Future<StaffUser> updateStaffUser(
    String id, {
    String? fullName,
    String? avatarUrl,
  }) async {
    AppLogger.info(_tag, 'Updating staff user: $id');
    try {
      final patch = <String, dynamic>{};
      if (fullName != null) patch['full_name'] = fullName.trim();
      if (avatarUrl != null) patch['avatar_url'] = avatarUrl;
      if (patch.isEmpty) {
        final existing = await getStaffUsers();
        return existing.firstWhere((u) => u.id == id);
      }
      final rows = await _client
          .from('staff_users')
          .update(patch)
          .eq('id', id)
          .select('id, full_name, team, role, avatar_url, password_hash');
      return StaffUser.fromJson((rows as List).first);
    } catch (e, st) {
      AppLogger.error(_tag, 'Failed to update staff user: $id', e, st);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Password management (via pgcrypto RPCs)
  // -------------------------------------------------------------------------

  /// Verify password. Returns false if no password is set yet.
  Future<bool> checkPassword(String staffId, String password) async {
    try {
      final result = await _client.rpc(
        'check_staff_password',
        params: {'p_staff_id': staffId, 'p_password': password},
      );
      return result as bool;
    } catch (e, st) {
      AppLogger.error(_tag, 'checkPassword failed', e, st);
      return false;
    }
  }

  /// Hash and persist a new password for a staff user.
  Future<void> setPassword(String staffId, String password) async {
    try {
      await _client.rpc(
        'set_staff_password',
        params: {'p_staff_id': staffId, 'p_password': password},
      );
      AppLogger.info(_tag, 'Password set for staff: $staffId');
    } catch (e, st) {
      AppLogger.error(_tag, 'setPassword failed', e, st);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Session (SharedPreferences)
  // -------------------------------------------------------------------------

  Future<String?> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  /// Load the current staff user using the saved session ID.
  /// Returns null (and clears the session) if the ID no longer exists in DB.
  Future<StaffUser?> getCurrentUser() async {
    final id = await getSessionId();
    if (id == null) return null;
    try {
      final staff = await getStaffUsers();
      final match = staff.where((s) => s.id == id).firstOrNull;
      if (match == null) {
        await clearSession();
        AppLogger.warn(_tag, 'Stale session cleared for id: $id');
      }
      return match;
    } catch (e, st) {
      AppLogger.error(_tag, 'getCurrentUser failed', e, st);
      return null;
    }
  }

  Future<void> saveSession(String staffId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, staffId);
    AppLogger.info(_tag, 'Session saved for staff: $staffId');
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    AppLogger.info(_tag, 'Session cleared');
  }

  /// Record the current timestamp as last-login for this staff member.
  Future<void> saveLastLogin(String staffId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$_lastLoginPrefix$staffId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Returns true if the last login for this staff member was within 14 days.
  Future<bool> isLoginRecent(String staffId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_lastLoginPrefix$staffId');
    if (ms == null) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - ms;
    return elapsed < const Duration(days: 14).inMilliseconds;
  }
}
