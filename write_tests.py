
attendance_test = '''// test/services/attendance_service_test.dart
//
// Unit tests for the attendance state machine.
//
// The _FT<T> helper wraps a plain Future<T> as PostgrestTransformBuilder<T>
// so that mocktail stubs for .maybeSingle() / .single() type-check correctly.
//
// Coverage:
//   1. clockInByOfflineCode -- absent guard (no DB needed)
//   2. AttendanceStatus.isTerminal -- pure logic
//   3. clockInMember -- terminal lock  (mocked chain)
//   4. clockInMember -- absent upgrade (mocked chain)
//   5. clockInMember -- new insert     (mocked chain)
//   6. clockInByOfflineCode -- happy path (mocked chain)
//   7. Sunday session team-scoping    (pure logic)

import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "package:attendance_app/models/enums.dart";
import "package:attendance_app/models/clock_in.dart";
import "package:attendance_app/models/member.dart";
import "package:attendance_app/services/attendance_service.dart";
import "package:attendance_app/services/member_service.dart";

// ---------------------------------------------------------------------------
// Mock declarations
// ---------------------------------------------------------------------------

class _MockClient extends Mock implements SupabaseClient {}
class _MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class _MockFilterBuilder extends Mock
    implements PostgrestFilterBuilder<PostgrestList> {}
class _MockMemberService extends Mock implements MemberService {}

/// Wraps a [Future<T>] as a [PostgrestTransformBuilder<T>].
/// Required because .maybeSingle() / .single() return PostgrestTransformBuilder
/// (a Future subtype) -- mocktail needs the exact static type.
class _FT<T> extends Fake implements PostgrestTransformBuilder<T> {
  _FT(T value) : _f = Future.value(value);
  final Future<T> _f;

  @override
  Future<R> then<R>(FutureOr<R> Function(T) fn, {Function? onError}) =>
      _f.then(fn, onError: onError);
  @override
  Future<T> catchError(Function fn, {bool Function(Object)? test}) =>
      _f.catchError(fn, test: test);
  @override
  Future<T> whenComplete(FutureOr<void> Function() fn) =>
      _f.whenComplete(fn);
  @override
  Stream<T> asStream() => _f.asStream();
  @override
  Future<T> timeout(Duration limit, {FutureOr<T> Function()? onTimeout}) =>
      _f.timeout(limit, onTimeout: onTimeout);
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

ClockIn _clockIn({AttendanceStatus status = AttendanceStatus.absent}) =>
    ClockIn(
      id: "ci-001", sessionId: "s-001", memberId: "m-001",
      status: status, method: ClockInMethod.manual,
      clockedAt: DateTime(2026, 3, 11, 9, 0),
    );

Member _member() => Member(
      id: "m-001", fullName: "Adaeze Okonkwo", phone: "08012345678",
      offlineCode: "123456", team: Team.teamA, isMarried: false,
      birthdayMD: "03-11", anniversaryMD: null,
      createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // 1. Absent guard

  group("clockInByOfflineCode -- absent guard", () {
    late _MockClient fakeClient;
    late _MockMemberService fakeMemberService;
    late AttendanceService service;

    setUp(() {
      fakeClient = _MockClient();
      fakeMemberService = _MockMemberService();
      service = AttendanceService(fakeClient, fakeMemberService);
    });

    test("throws before any DB call", () {
      expect(
        () => service.clockInByOfflineCode(
            sessionId: "s-001", code: "123456",
            status: AttendanceStatus.absent),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), "msg", contains("absent"))),
      );
      verifyNever(() => fakeClient.from(any()));
    });

    test("passes guard for present, fails on Member not found", () {
      when(() => fakeMemberService.getMemberByOfflineCode(any()))
          .thenAnswer((_) async => null);
      expect(
        () => service.clockInByOfflineCode(
            sessionId: "s-001", code: "000000"),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), "msg", contains("Member not found"))),
      );
    });
  });

  // 2. isTerminal

  group("AttendanceStatus.isTerminal", () {
    test("present is terminal",
        () => expect(AttendanceStatus.present.isTerminal, isTrue));
    test("excused is terminal",
        () => expect(AttendanceStatus.excused.isTerminal, isTrue));
    test("absent is NOT terminal",
        () => expect(AttendanceStatus.absent.isTerminal, isFalse));
  });

  // 3. Terminal lock

  group("clockInMember -- terminal lock", () {
    late _MockClient mockClient;
    late _MockQueryBuilder mockQB;
    late _MockFilterBuilder mockFB;
    late AttendanceService service;

    void stubFind(Map<String, dynamic>? result) {
      when(() => mockClient.from("clock_ins")).thenReturn(mockQB);
      when(() => mockQB.select()).thenReturn(mockFB);
      when(() => mockFB.eq(any(), any())).thenReturn(mockFB);
      when(() => mockFB.maybeSingle()).thenReturn(_FT<PostgrestMap?>(result));
    }

    setUp(() {
      mockClient = _MockClient();
      mockQB = _MockQueryBuilder();
      mockFB = _MockFilterBuilder();
      service = AttendanceService(mockClient, _MockMemberService());
    });

    test("throws Already marked for present", () {
      stubFind(_clockIn(status: AttendanceStatus.present).toJson());
      expect(
        () => service.clockInMember(sessionId: "s-001", memberId: "m-001"),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), "msg", contains("Already marked"))),
      );
    });

    test("throws Already marked for excused", () {
      stubFind(_clockIn(status: AttendanceStatus.excused).toJson());
      expect(
        () => service.clockInMember(sessionId: "s-001", memberId: "m-001"),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), "msg", contains("Already marked"))),
      );
    });
  });

  // 4. Absent upgrade

  group("clockInMember -- absent upgrade", () {
    late _MockClient mockClient;
    late _MockQueryBuilder mockQB;
    late _MockFilterBuilder mockFB;
    late AttendanceService service;

    setUp(() {
      mockClient = _MockClient();
      mockQB = _MockQueryBuilder();
      mockFB = _MockFilterBuilder();
      service = AttendanceService(mockClient, _MockMemberService());

      when(() => mockClient.from("clock_ins")).thenReturn(mockQB);
      when(() => mockQB.select()).thenReturn(mockFB);
      when(() => mockFB.eq(any(), any())).thenReturn(mockFB);
      when(() => mockFB.maybeSingle()).thenReturn(
          _FT<PostgrestMap?>(_clockIn(status: AttendanceStatus.absent).toJson()));
      when(() => mockQB.update(any())).thenReturn(mockFB);
    });

    test("upgrades absent to present", () async {
      final r = await service.clockInMember(
          sessionId: "s-001", memberId: "m-001",
          status: AttendanceStatus.present);
      expect(r.status, AttendanceStatus.present);
    });

    test("upgrades absent to excused", () async {
      final r = await service.clockInMember(
          sessionId: "s-001", memberId: "m-001",
          status: AttendanceStatus.excused);
      expect(r.status, AttendanceStatus.excused);
    });
  });

  // 5. New insert

  group("clockInMember -- new insert", () {
    late _MockClient mockClient;
    late _MockQueryBuilder mockQB;
    late _MockFilterBuilder mockFB;
    late AttendanceService service;

    setUp(() {
      mockClient = _MockClient();
      mockQB = _MockQueryBuilder();
      mockFB = _MockFilterBuilder();
      service = AttendanceService(mockClient, _MockMemberService());

      when(() => mockClient.from("clock_ins")).thenReturn(mockQB);
      when(() => mockQB.select()).thenReturn(mockFB);
      when(() => mockFB.eq(any(), any())).thenReturn(mockFB);
      when(() => mockFB.maybeSingle()).thenReturn(_FT<PostgrestMap?>(null));
      when(() => mockQB.insert(any())).thenReturn(mockFB);
      when(() => mockFB.select(any())).thenReturn(mockFB);
      when(() => mockFB.single()).thenReturn(_FT<PostgrestMap>(
          _clockIn(status: AttendanceStatus.present).toJson()));
    });

    test("returns new ClockIn with correct fields", () async {
      final r = await service.clockInMember(
          sessionId: "s-001", memberId: "m-001");
      expect(r.status, AttendanceStatus.present);
      expect(r.sessionId, "s-001");
    });

    test("calls insert exactly once", () async {
      await service.clockInMember(sessionId: "s-001", memberId: "m-001");
      verify(() => mockQB.insert(any())).called(1);
    });
  });

  // 6. clockInByOfflineCode happy path

  group("clockInByOfflineCode -- happy path", () {
    late _MockClient mockClient;
    late _MockQueryBuilder mockQB;
    late _MockFilterBuilder mockFB;
    late _MockMemberService mockMS;
    late AttendanceService service;

    setUp(() {
      mockClient = _MockClient();
      mockQB = _MockQueryBuilder();
      mockFB = _MockFilterBuilder();
      mockMS = _MockMemberService();
      service = AttendanceService(mockClient, mockMS);

      when(() => mockMS.getMemberByOfflineCode("123456"))
          .thenAnswer((_) async => _member());
      when(() => mockClient.from("clock_ins")).thenReturn(mockQB);
      when(() => mockQB.select()).thenReturn(mockFB);
      when(() => mockFB.eq(any(), any())).thenReturn(mockFB);
      when(() => mockFB.maybeSingle()).thenReturn(_FT<PostgrestMap?>(null));
      when(() => mockQB.insert(any())).thenReturn(mockFB);
      when(() => mockFB.select(any())).thenReturn(mockFB);
      when(() => mockFB.single()).thenReturn(_FT<PostgrestMap>(
          _clockIn(status: AttendanceStatus.present).toJson()));
    });

    test("marks member present by offline code", () async {
      final r = await service.clockInByOfflineCode(
          sessionId: "s-001", code: "123456");
      expect(r.status, AttendanceStatus.present);
      expect(r.memberId, "m-001");
    });
  });

  // 7. Sunday team-scoping

  group("Sunday session team-scoping", () {
    Team? infer(String name) {
      final n = name.toLowerCase();
      if (n.contains("service 1") || n.contains("first")) return Team.teamA;
      if (n.contains("service 2") || n.contains("second")) return Team.teamB;
      if (n.contains("service 3") || n.contains("third")) return Team.teamC;
      return null;
    }

    test("Service 1 -> Team A", () => expect(infer("Service 1"), Team.teamA));
    test("first service -> Team A", () =>
        expect(infer("first service"), Team.teamA));
    test("Service 2 -> Team B", () => expect(infer("Service 2"), Team.teamB));
    test("Service 3 -> Team C", () => expect(infer("Service 3"), Team.teamC));
    test("Unknown -> null", () => expect(infer("General Session"), isNull));

    test("Service 1 scopes to Team A members only", () {
      final teamA = Member(
        id: "a", fullName: "Alice", phone: "", offlineCode: "100000",
        team: Team.teamA, isMarried: false, birthdayMD: "01-01",
        anniversaryMD: null, createdAt: DateTime(2026), updatedAt: DateTime(2026),
      );
      final teamB = Member(
        id: "b", fullName: "Bob", phone: "", offlineCode: "100001",
        team: Team.teamB, isMarried: false, birthdayMD: "01-02",
        anniversaryMD: null, createdAt: DateTime(2026), updatedAt: DateTime(2026),
      );
      final scoped =
          [teamA, teamB].where((m) => m.team == infer("Service 1")).toList();
      expect(scoped, [teamA]);
      expect(scoped, isNot(contains(teamB)));
    });
  });
}
'''

member_test = '''// test/services/member_service_test.dart
//
// Unit tests for MemberService.
//
// Coverage:
//   1. Member model -- fromJson / toJson round-trip
//   2. getMemberByOfflineCode -- not found, found
//   3. createMember -- basic insert, anniversary nulled for non-married
//   4. deleteMember -- calls delete with correct id

import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "package:attendance_app/models/member.dart";
import "package:attendance_app/models/enums.dart";
import "package:attendance_app/services/member_service.dart";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockClient extends Mock implements SupabaseClient {}
class _MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class _MockFilterBuilder extends Mock
    implements PostgrestFilterBuilder<PostgrestList> {}

class _FT<T> extends Fake implements PostgrestTransformBuilder<T> {
  _FT(T value) : _f = Future.value(value);
  final Future<T> _f;

  @override
  Future<R> then<R>(FutureOr<R> Function(T) fn, {Function? onError}) =>
      _f.then(fn, onError: onError);
  @override
  Future<T> catchError(Function fn, {bool Function(Object)? test}) =>
      _f.catchError(fn, test: test);
  @override
  Future<T> whenComplete(FutureOr<void> Function() fn) =>
      _f.whenComplete(fn);
  @override
  Stream<T> asStream() => _f.asStream();
  @override
  Future<T> timeout(Duration limit, {FutureOr<T> Function()? onTimeout}) =>
      _f.timeout(limit, onTimeout: onTimeout);
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

Map<String, dynamic> _memberJson({
  String id = "m-new-001",
  String fullName = "Chioma Eze",
  String phone = "08099887766",
  String offlineCode = "550123",
  String team = "Team B",
  bool isMarried = false,
  String birthdayMD = "07-04",
  String? anniversaryMD,
}) =>
    {
      "id": id,
      "full_name": fullName,
      "phone": phone,
      "offline_code": offlineCode,
      "team": team,
      "is_married": isMarried,
      "birthday_md": birthdayMD,
      "anniversary_md": anniversaryMD,
      "created_at": "2026-03-11T09:00:00.000Z",
      "updated_at": "2026-03-11T09:00:00.000Z",
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // 1. Model round-trip

  group("Member model", () {
    test("fromJson preserves all fields", () {
      final m = Member.fromJson(_memberJson());
      expect(m.id, "m-new-001");
      expect(m.fullName, "Chioma Eze");
      expect(m.phone, "08099887766");
      expect(m.offlineCode, "550123");
      expect(m.team, Team.teamB);
      expect(m.isMarried, isFalse);
      expect(m.birthdayMD, "07-04");
      expect(m.anniversaryMD, isNull);
    });

    test("fromJson defaults phone to empty string when missing", () {
      final json = _memberJson()..remove("phone");
      expect(Member.fromJson(json).phone, "");
    });

    test("fromJson defaults is_married to false when missing", () {
      final json = _memberJson()..remove("is_married");
      expect(Member.fromJson(json).isMarried, isFalse);
    });

    test("toJson uses snake_case keys for Supabase", () {
      final json = Member.fromJson(_memberJson()).toJson();
      expect(json["full_name"], "Chioma Eze");
      expect(json["offline_code"], "550123");
      expect(json["birthday_md"], "07-04");
    });

    test("toInsertJson omits id, created_at, updated_at", () {
      final json = Member.fromJson(_memberJson()).toInsertJson();
      expect(json.containsKey("id"), isFalse);
      expect(json.containsKey("created_at"), isFalse);
      expect(json["full_name"], "Chioma Eze");
    });

    test("copyWith updates only specified fields", () {
      final original = Member.fromJson(_memberJson());
      final updated = original.copyWith(fullName: "Chioma Okafor");
      expect(updated.fullName, "Chioma Okafor");
      expect(updated.id, original.id);
      expect(updated.offlineCode, original.offlineCode);
    });
  });

  // 2. getMemberByOfflineCode

  group("MemberService.getMemberByOfflineCode", () {
    late _MockClient mockClient;
    late _MockQueryBuilder mockQB;
    late _MockFilterBuilder mockFB;
    late MemberService service;

    setUp(() {
      mockClient = _MockClient();
      mockQB = _MockQueryBuilder();
      mockFB = _MockFilterBuilder();
      service = MemberService(mockClient);

      when(() => mockClient.from("members")).thenReturn(mockQB);
      when(() => mockQB.select(any())).thenReturn(mockFB);
      when(() => mockFB.eq(any(), any())).thenReturn(mockFB);
    });

    test("returns null when member not found", () async {
      when(() => mockFB.maybeSingle())
          .thenReturn(_FT<PostgrestMap?>(null));
      expect(await service.getMemberByOfflineCode("000000"), isNull);
    });

    test("returns Member when code matches", () async {
      when(() => mockFB.maybeSingle())
          .thenReturn(_FT<PostgrestMap?>(_memberJson(offlineCode: "550123")));
      final m = await service.getMemberByOfflineCode("550123");
      expect(m, isNotNull);
      expect(m!.offlineCode, "550123");
    });
  });

  // 3. createMember

  group("MemberService.createMember", () {
    late _MockClient mockClient;
    late _MockQueryBuilder mockQB;
    late _MockFilterBuilder mockFB;
    late MemberService service;

    setUp(() {
      mockClient = _MockClient();
      mockQB = _MockQueryBuilder();
      mockFB = _MockFilterBuilder();
      service = MemberService(mockClient);

      // Code uniqueness check -> available
      when(() => mockClient.from("members")).thenReturn(mockQB);
      when(() => mockQB.select(any())).thenReturn(mockFB);
      when(() => mockFB.eq(any(), any())).thenReturn(mockFB);
      when(() => mockFB.maybeSingle()).thenReturn(_FT<PostgrestMap?>(null));

      // Insert
      when(() => mockQB.insert(any())).thenReturn(mockFB);
      when(() => mockFB.select(any())).thenReturn(mockFB);
      when(() => mockFB.single())
          .thenReturn(_FT<PostgrestMap>(_memberJson()));
    });

    test("returns the created Member", () async {
      final m = await service.createMember(
        fullName: "Chioma Eze",
        phone: "08099887766",
        team: Team.teamB,
        isMarried: false,
        birthdayMD: "07-04",
      );
      expect(m.fullName, "Chioma Eze");
      expect(m.team, Team.teamB);
    });

    test("nulls anniversary for non-married member", () async {
      await service.createMember(
        fullName: "Chioma Eze",
        phone: "08099887766",
        team: Team.teamB,
        isMarried: false,
        birthdayMD: "07-04",
        anniversaryMD: "should-be-ignored",
      );
      final captured =
          verify(() => mockQB.insert(captureAny())).captured.first
              as Map<String, dynamic>;
      expect(captured["anniversary_md"], isNull);
    });

    test("preserves anniversary for married member", () async {
      when(() => mockFB.single())
          .thenReturn(_FT<PostgrestMap>(
              _memberJson(isMarried: true, anniversaryMD: "06-15")));
      await service.createMember(
        fullName: "Ngozi Adeyemi",
        phone: "08011223344",
        team: Team.teamC,
        isMarried: true,
        birthdayMD: "04-21",
        anniversaryMD: "06-15",
      );
      final captured =
          verify(() => mockQB.insert(captureAny())).captured.first
              as Map<String, dynamic>;
      expect(captured["anniversary_md"], "06-15");
    });
  });

  // 4. deleteMember

  group("MemberService.deleteMember", () {
    late _MockClient mockClient;
    late _MockQueryBuilder mockQB;
    late _MockFilterBuilder mockFB;
    late MemberService service;

    setUp(() {
      mockClient = _MockClient();
      mockQB = _MockQueryBuilder();
      mockFB = _MockFilterBuilder();
      service = MemberService(mockClient);

      when(() => mockClient.from("members")).thenReturn(mockQB);
      when(() => mockQB.delete()).thenReturn(mockFB);
      when(() => mockFB.eq(any(), any()))
          .thenReturn(_FT<PostgrestList>([]));
    });

    test("calls delete and filters by id", () async {
      await service.deleteMember("m-001");
      verify(() => mockQB.delete()).called(1);
      verify(() => mockFB.eq("id", "m-001")).called(1);
    });
  });
}
'''

import os

base = "c:/Users/DELL.COM/Desktop/Darey/Guest-Welcome-attendance-app/flutter_app/test/services"
os.makedirs(base, exist_ok=True)

with open(f"{base}/attendance_service_test.dart", "w") as f:
    f.write(attendance_test)
print("attendance_service_test.dart written")

with open(f"{base}/member_service_test.dart", "w") as f:
    f.write(member_test)
print("member_service_test.dart written")
