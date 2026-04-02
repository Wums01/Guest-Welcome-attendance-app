// lib/services/member_service.dart
//
// Dart equivalent of lib/core/members.ts
// All localStorage operations replaced with Supabase queries.

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member.dart';
import '../models/enums.dart';
import '../core/logger.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final memberServiceProvider = Provider<MemberService>(
  (ref) => MemberService(Supabase.instance.client),
);

// ---------------------------------------------------------------------------
// MemberService
// ---------------------------------------------------------------------------

class MemberService {
  MemberService(this._client);
  final SupabaseClient _client;

  static const _table = 'members';
  static const _tag = 'MemberService';

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<Member>> getMembers() async {
    AppLogger.info(_tag, 'getMembers()');
    try {
      final data = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false);
      final members = (data as List).map((e) => Member.fromJson(e)).toList();
      AppLogger.info(_tag, 'getMembers → ${members.length} members');
      return members;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getMembers failed', e, stack);
      rethrow;
    }
  }

  Future<Member?> getMemberById(String id) async {
    AppLogger.info(_tag, 'getMemberById($id)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) {
        AppLogger.warn(_tag, 'getMemberById($id) → not found');
        return null;
      }
      final member = Member.fromJson(data);
      AppLogger.info(_tag, 'getMemberById($id) → "${member.fullName}"');
      return member;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getMemberById($id) failed', e, stack);
      rethrow;
    }
  }

  /// Looks up a member by their 6-digit offline code.
  /// This is the hot path called on every code-based check-in.
  Future<Member?> getMemberByOfflineCode(String code) async {
    AppLogger.info(_tag, 'getMemberByOfflineCode($code)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('offline_code', code)
          .maybeSingle();
      if (data == null) {
        AppLogger.warn(_tag, 'getMemberByOfflineCode($code) → not found');
        return null;
      }
      final member = Member.fromJson(data);
      AppLogger.info(_tag, 'getMemberByOfflineCode($code) → "${member.fullName}"');
      return member;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getMemberByOfflineCode($code) failed', e, stack);
      rethrow;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Creates a new member.
  /// Generates a unique 6-digit offline code before inserting
  /// (mirrors the TypeScript generate6DigitCode logic).
  Future<Member> createMember({
    required String fullName,
    required String phone,
    required Team team,
    required bool isMarried,
    required String birthdayMD,
    String? anniversaryMD,
  }) async {
    AppLogger.info(_tag, 'createMember(name: "$fullName", team: ${team.value})');
    try {
      final offlineCode = await _generateUniqueCode();

      final insert = {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'offline_code': offlineCode,
        'team': team.value,
        'is_married': isMarried,
        'birthday_md': birthdayMD,
        'anniversary_md': isMarried ? anniversaryMD : null,
      };

      final data = await _client.from(_table).insert(insert).select().single();
      final member = Member.fromJson(data);
      AppLogger.info(
        _tag,
        'createMember → created "${member.fullName}" (id: ${member.id}, code: $offlineCode)',
      );
      return member;
    } catch (e, stack) {
      AppLogger.error(_tag, 'createMember(name: "$fullName") failed', e, stack);
      rethrow;
    }
  }

  Future<void> deleteMember(String id) async {
    AppLogger.warn(_tag, 'deleteMember($id)');
    try {
      // Cascade delete: deleting a member also deletes all their attendance records
      await _client.from(_table).delete().eq('id', id);
      AppLogger.info(_tag, 'deleteMember($id) → ok');
    } catch (e, stack) {
      AppLogger.error(_tag, 'deleteMember($id) failed', e, stack);
      rethrow;
    }
  }

  Future<Member> updateMember(
    String id, {
    String? fullName,
    String? phone,
    Team? team,
    bool? isMarried,
    String? birthdayMD,
    String? anniversaryMD,
    String? photoUrl,
  }) async {
    AppLogger.info(_tag, 'updateMember($id)');
    try {
      final patch = <String, dynamic>{};
      if (fullName != null) patch['full_name'] = fullName.trim();
      if (phone != null) patch['phone'] = phone.trim();
      if (team != null) patch['team'] = team.value;
      if (isMarried != null) patch['is_married'] = isMarried;
      if (birthdayMD != null) patch['birthday_md'] = birthdayMD;
      if (anniversaryMD != null) patch['anniversary_md'] = anniversaryMD;
      if (photoUrl != null) patch['photo_url'] = photoUrl;
      if (patch.isEmpty) {
        final existing = await getMemberById(id);
        if (existing == null) throw Exception('Member not found');
        return existing;
      }
      final data = await _client
          .from(_table)
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      final member = Member.fromJson(data);
      AppLogger.info(_tag, 'updateMember($id) → ok');
      return member;
    } catch (e, stack) {
      AppLogger.error(_tag, 'updateMember($id) failed', e, stack);
      rethrow;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Generates a random 6-digit code that does not already exist in the DB.
  /// Tries up to 30 times before throwing — same logic as the TypeScript version.
  Future<String> _generateUniqueCode() async {
    AppLogger.debug(_tag, '_generateUniqueCode: searching for unique 6-digit code');
    final rng = Random();
    for (int i = 0; i < 30; i++) {
      final code =
          (100000 + rng.nextInt(900000)).toString(); // 100000–999999
      final existing = await _client
          .from(_table)
          .select('id')
          .eq('offline_code', code)
          .maybeSingle();
      if (existing == null) {
        AppLogger.debug(_tag, '_generateUniqueCode → found unique code (attempt ${i + 1})');
        return code;
      }
    }
    AppLogger.error(_tag, '_generateUniqueCode → exhausted 30 attempts');
    throw Exception(
        'Could not generate a unique offline code after 30 attempts. Try again.');
  }
}
