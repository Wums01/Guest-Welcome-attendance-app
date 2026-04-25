// lib/services/achievement_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/logger.dart';
import '../models/achievement.dart';

final achievementServiceProvider = Provider<AchievementService>(
  (ref) => AchievementService(Supabase.instance.client),
);

class AchievementService {
  AchievementService(this._client);
  final SupabaseClient _client;

  static const _tag = 'AchievementService';

  Future<List<Achievement>> getAchievementsForMember(
      String memberId) async {
    AppLogger.info(_tag, 'getAchievementsForMember($memberId)');
    try {
      final data = await _client
          .from('member_achievements')
          .select()
          .eq('member_id', memberId)
          .order('achieved_at', ascending: false);
      final list =
          (data as List).map((e) => Achievement.fromJson(e)).toList();
      AppLogger.info(
          _tag, 'getAchievementsForMember($memberId) → ${list.length}');
      return list;
    } catch (e, stack) {
      AppLogger.error(
          _tag, 'getAchievementsForMember($memberId) failed', e, stack);
      rethrow;
    }
  }

  /// Triggers the Edge Function to evaluate achievements server-side.
  Future<void> evaluateAchievements() async {
    AppLogger.info(_tag, 'evaluateAchievements()');
    try {
      await _client.functions.invoke('evaluate-achievements');
    } catch (e, stack) {
      AppLogger.error(_tag, 'evaluateAchievements() failed', e, stack);
      rethrow;
    }
  }
}
