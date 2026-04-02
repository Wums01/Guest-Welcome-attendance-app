// test/services/member_service_test.dart
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


/// Fake awaitable PostgrestFilterBuilder -- used for terminal .eq() in DELETE chains.
/// Unlike _FT which implements PostgrestTransformBuilder, this implements
/// PostgrestFilterBuilder (a subtype) so it type-checks for .eq() return values.
class _FakeFB extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  @override
  Future<R> then<R>(FutureOr<R> Function(PostgrestList) fn,
          {Function? onError}) =>
      Future.value(<Map<String, dynamic>>[]).then(fn, onError: onError);
  @override
  Future<PostgrestList> catchError(Function fn,
          {bool Function(Object)? test}) =>
      Future.value(<Map<String, dynamic>>[]).catchError(fn, test: test);
  @override
  Future<PostgrestList> whenComplete(FutureOr<void> Function() fn) =>
      Future.value(<Map<String, dynamic>>[]).whenComplete(fn);
  @override
  Stream<PostgrestList> asStream() => Stream.value([]);
  @override
  Future<PostgrestList> timeout(Duration limit,
          {FutureOr<PostgrestList> Function()? onTimeout}) =>
      Future.value(<Map<String, dynamic>>[]).timeout(limit, onTimeout: onTimeout);
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

      when(() => mockClient.from("members")).thenAnswer((_) => mockQB);
      when(() => mockQB.select(any())).thenAnswer((_) => mockFB);
      when(() => mockFB.eq(any(), any())).thenAnswer((_) => mockFB);
    });

    test("returns null when member not found", () async {
      when(() => mockFB.maybeSingle())
          .thenAnswer((_) => _FT<PostgrestMap?>(null));
      expect(await service.getMemberByOfflineCode("000000"), isNull);
    });

    test("returns Member when code matches", () async {
      when(() => mockFB.maybeSingle())
          .thenAnswer((_) => _FT<PostgrestMap?>(_memberJson(offlineCode: "550123")));
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
      when(() => mockClient.from("members")).thenAnswer((_) => mockQB);
      when(() => mockQB.select(any())).thenAnswer((_) => mockFB);
      when(() => mockFB.eq(any(), any())).thenAnswer((_) => mockFB);
      when(() => mockFB.maybeSingle()).thenAnswer((_) => _FT<PostgrestMap?>(null));

      // Insert
      when(() => mockQB.insert(any())).thenAnswer((_) => mockFB);
      when(() => mockFB.select(any())).thenAnswer((_) => mockFB);
      when(() => mockFB.single())
          .thenAnswer((_) => _FT<PostgrestMap>(_memberJson()));
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
          .thenAnswer((_) => _FT<PostgrestMap>(
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

      when(() => mockClient.from("members")).thenAnswer((_) => mockQB);
      when(() => mockQB.delete()).thenAnswer((_) => mockFB);
      when(() => mockFB.eq(any(), any()))
          .thenAnswer((_) => _FakeFB());
    });

    test("calls delete and filters by id", () async {
      await service.deleteMember("m-001");
      verify(() => mockQB.delete()).called(1);
      verify(() => mockFB.eq("id", "m-001")).called(1);
    });
  });
}
