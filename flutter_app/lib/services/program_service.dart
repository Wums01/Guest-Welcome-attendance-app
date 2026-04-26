// lib/services/program_service.dart
//
// Dart equivalent of lib/core/programs.ts
// All localStorage operations replaced with Supabase queries.
//
// Business rules preserved:
//   - Non-TBD programs: startDate required, endDate >= startDate
//   - TBD programs: both dates are null
//   - deleteProgram cascades to sessions (handled by DB CASCADE + explicit call)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/program.dart';
import '../models/enums.dart';
import '../core/logger.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final programServiceProvider = Provider<ProgramService>(
  (ref) => ProgramService(Supabase.instance.client),
);

// ---------------------------------------------------------------------------
// ProgramService
// ---------------------------------------------------------------------------

class ProgramService {
  ProgramService(this._client);
  final SupabaseClient _client;

  static const _table = 'programs';
  static const _tag = 'ProgramService';

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<Program>> getPrograms() async {
    AppLogger.info(_tag, 'getPrograms()');
    try {
      final data = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false);
      final programs = (data as List).map((e) => Program.fromJson(e)).toList();
      AppLogger.info(_tag, 'getPrograms → ${programs.length} programs');
      return programs;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getPrograms failed', e, stack);
      rethrow;
    }
  }

  Future<Program?> getProgramById(String id) async {
    AppLogger.info(_tag, 'getProgramById($id)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) {
        AppLogger.warn(_tag, 'getProgramById($id) → not found');
        return null;
      }
      final program = Program.fromJson(data);
      AppLogger.info(_tag, 'getProgramById($id) → "${program.title}"');
      return program;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getProgramById($id) failed', e, stack);
      rethrow;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<Program> createProgram({
    required String title,
    required ProgramType programType,
    required String? teamScope,
    required bool isTBD,
    String? startDate,
    String? endDate,
    bool isVirtual = false,
  }) async {
    AppLogger.info(_tag, 'createProgram(title: "$title", type: ${programType.value}, tbd: $isTBD, virtual: $isVirtual)');
    try {
      // ── Business rule validation ──────────────────────────────────────────
      if (!isTBD) {
        if (startDate == null || startDate.isEmpty) {
          throw Exception(
              'Please enter a start date');
        }
        if (endDate == null || endDate.isEmpty) {
          throw Exception(
              'Please enter an end date');
        }
        if (endDate.compareTo(startDate) < 0) {
          throw Exception('The end date must be after the start date.');
        }
      }

      final insert = {
        'title': title.trim(),
        'program_type': programType.value,
        'is_tbd': isTBD,
        'start_date': isTBD ? null : startDate,
        'end_date': isTBD ? null : endDate,
        'team_scope': teamScope,
        'is_virtual': isVirtual,
      };

      final data =
          await _client.from(_table).insert(insert).select().single();
      final program = Program.fromJson(data);
      AppLogger.info(_tag, 'createProgram → created "${program.title}" (${program.id})');
      return program;
    } catch (e, stack) {
      AppLogger.error(_tag, 'createProgram(title: "$title") failed', e, stack);
      rethrow;
    }
  }

  Future<void> updateProgram(
    String programId, {
    String? title,
    ProgramType? programType,
    bool? isTBD,
    String? startDate,
    String? endDate,
    String? teamScope,
    bool? isVirtual,
  }) async {
    AppLogger.info(_tag, 'updateProgram($programId)');
    try {
      final current = await getProgramById(programId);
      if (current == null) {
        AppLogger.warn(_tag, 'updateProgram($programId) → not found, skipping');
        return;
      }

      final nextIsTBD = isTBD ?? current.isTBD;
      final nextStart = nextIsTBD ? null : (startDate ?? current.startDate);
      final nextEnd   = nextIsTBD ? null : (endDate ?? current.endDate);

      // ── Business rule validation ──────────────────────────────────────────
      if (!nextIsTBD) {
        if (nextStart == null || nextEnd == null) {
          throw Exception(
              'Please enter both start and end dates.');
        }
        if (nextEnd.compareTo(nextStart) < 0) {
          throw Exception('The end date must be after the start date.');
        }
      }

      await _client.from(_table).update({
        'title': (title ?? current.title).trim(),
        'program_type': (programType ?? current.programType).value,
        'is_tbd': nextIsTBD,
        'start_date': nextStart,
        'end_date': nextEnd,
        'team_scope': teamScope ?? current.teamScope,
        'is_virtual': isVirtual ?? current.isVirtual,
      }).eq('id', programId);

      AppLogger.info(_tag, 'updateProgram($programId) → ok');
    } catch (e, stack) {
      AppLogger.error(_tag, 'updateProgram($programId) failed', e, stack);
      rethrow;
    }
  }

  /// Deletes a program.
  /// The DB CASCADE on sessions.program_id handles session removal automatically.
  /// Session CASCADE on clock_ins.session_id handles attendance removal too.
  Future<void> deleteProgram(String programId) async {
    AppLogger.warn(_tag, 'deleteProgram($programId)');
    try {
      await _client.from(_table).delete().eq('id', programId);
      AppLogger.info(_tag, 'deleteProgram($programId) → ok');
    } catch (e, stack) {
      AppLogger.error(_tag, 'deleteProgram($programId) failed', e, stack);
      rethrow;
    }
  }
}
