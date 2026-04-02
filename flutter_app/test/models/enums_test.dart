// test/models/enums_test.dart
//
// Pure unit tests for all enum business logic.
// No Supabase connection required — runs fully offline.

import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_app/models/enums.dart';

void main() {
  // ── AttendanceStatus ───────────────────────────────────────────────────────

  group('AttendanceStatus', () {
    group('isTerminal', () {
      test('present is terminal (locked)', () {
        expect(AttendanceStatus.present.isTerminal, isTrue);
      });

      test('excused is terminal (locked)', () {
        expect(AttendanceStatus.excused.isTerminal, isTrue);
      });

      test('absent is NOT terminal (can be upgraded)', () {
        expect(AttendanceStatus.absent.isTerminal, isFalse);
      });
    });

    group('fromValue()', () {
      test('parses "present"', () {
        expect(AttendanceStatus.fromValue('present'), AttendanceStatus.present);
      });

      test('parses "absent"', () {
        expect(AttendanceStatus.fromValue('absent'), AttendanceStatus.absent);
      });

      test('parses "excused"', () {
        expect(AttendanceStatus.fromValue('excused'), AttendanceStatus.excused);
      });

      test('throws ArgumentError on unknown value', () {
        expect(
          () => AttendanceStatus.fromValue('unknown'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    test('value getter returns DB-compatible string', () {
      expect(AttendanceStatus.present.value, 'present');
      expect(AttendanceStatus.absent.value, 'absent');
      expect(AttendanceStatus.excused.value, 'excused');
    });
  });

  // ── Team ──────────────────────────────────────────────────────────────────

  group('Team', () {
    group('fromValue()', () {
      test('parses "Team A"', () {
        expect(Team.fromValue('Team A'), Team.teamA);
      });

      test('parses "Team B"', () {
        expect(Team.fromValue('Team B'), Team.teamB);
      });

      test('parses "Team C"', () {
        expect(Team.fromValue('Team C'), Team.teamC);
      });

      test('parses "None"', () {
        expect(Team.fromValue('None'), Team.none);
      });

      test('throws ArgumentError on unknown team', () {
        expect(
          () => Team.fromValue('Team X'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    test('value getter returns DB-compatible string', () {
      expect(Team.teamA.value, 'Team A');
      expect(Team.teamB.value, 'Team B');
      expect(Team.teamC.value, 'Team C');
      expect(Team.none.value, 'None');
    });

    test('toString() returns the DB string (used in JSON serialization)', () {
      expect(Team.teamA.toString(), 'Team A');
    });
  });

  // ── ProgramType ───────────────────────────────────────────────────────────

  group('ProgramType', () {
    group('fromValue()', () {
      test('parses all values', () {
        expect(ProgramType.fromValue('sunday'), ProgramType.sunday);
        expect(ProgramType.fromValue('wednesday'), ProgramType.wednesday);
        expect(ProgramType.fromValue('program'), ProgramType.program);
        expect(ProgramType.fromValue('meeting'), ProgramType.meeting);
        expect(ProgramType.fromValue('training'), ProgramType.training);
      });

      test('throws ArgumentError on unknown value', () {
        expect(
          () => ProgramType.fromValue('saturday'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('displayName', () {
      test('sunday → "Sunday Service"', () {
        expect(ProgramType.sunday.displayName, 'Sunday Service');
      });

      test('wednesday → "Wednesday Service"', () {
        expect(ProgramType.wednesday.displayName, 'Wednesday Service');
      });

      test('program → "Program"', () {
        expect(ProgramType.program.displayName, 'Program');
      });
    });
  });

  // ── ClockInMethod ─────────────────────────────────────────────────────────

  group('ClockInMethod', () {
    test('offlineCode value is "offline_code" (DB enum string)', () {
      // Critical: the DB stores "offline_code" not "offlineCode"
      expect(ClockInMethod.offlineCode.value, 'offline_code');
    });

    group('fromValue()', () {
      test('parses "offline_code"', () {
        expect(ClockInMethod.fromValue('offline_code'), ClockInMethod.offlineCode);
      });

      test('parses "manual"', () {
        expect(ClockInMethod.fromValue('manual'), ClockInMethod.manual);
      });

      test('throws ArgumentError on unknown value', () {
        expect(
          () => ClockInMethod.fromValue('nfc'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
