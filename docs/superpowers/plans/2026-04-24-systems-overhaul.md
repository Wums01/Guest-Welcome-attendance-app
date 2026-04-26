# Systems Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real points/achievements system, extend follow-up tracking, replace client-side birthday notifications with server-side FCM push, and wire up deep-linked push notifications across all staff devices.

**Architecture:** Hybrid — all state in Supabase (single source of truth, accurate across every device); database triggers award points; Edge Functions handle scheduled push (FCM HTTP v1); Flutter is display-only.

**Tech Stack:** Flutter 3 / Riverpod, Supabase (PostgreSQL + Edge Functions + pg_cron), Firebase Cloud Messaging (FCM HTTP v1), `firebase_messaging` Flutter package, `mocktail` for tests.

**Spec:** `docs/superpowers/specs/2026-04-24-systems-overhaul-design.md`

---

## File Map

### New migrations
| File | Purpose |
|---|---|
| `supabase/migrations/20260424000000_create_points_ledger.sql` | `points_ledger` table + `award_attendance_point` trigger |
| `supabase/migrations/20260424000001_update_leaderboard_views.sql` | Rebuild views to include `total_points` |
| `supabase/migrations/20260424000002_create_member_achievements.sql` | `member_achievements` table + `get_member_streak()` function |
| `supabase/migrations/20260424000003_extend_follow_up_actions.sql` | Rename `action`→`action_type`, add `scheduled_follow_up_at`, `outcome_note` |
| `supabase/migrations/20260424000004_create_device_tokens.sql` | `device_tokens` table for FCM tokens |
| `supabase/migrations/20260424000005_create_birthday_notification_log.sql` | Dedup log for birthday/anniversary push |
| `supabase/migrations/20260424000006_schedule_notification_crons.sql` | Documents cron schedule (applied via Dashboard) |

### New Edge Functions
| File | Purpose |
|---|---|
| `supabase/functions/send-push/index.ts` | Shared FCM HTTP v1 wrapper — called by all other functions |
| `supabase/functions/evaluate-achievements/index.ts` | Idempotently unlock achievements for all members |
| `supabase/functions/notify-birthdays/index.ts` | Eve (9 PM) + morning (8 AM) birthday/anniversary push |
| `supabase/functions/follow-up-reminders/index.ts` | Daily 8 AM push for due follow-up actions |

### New Flutter files
| File | Purpose |
|---|---|
| `flutter_app/lib/models/achievement.dart` | `Achievement` model |
| `flutter_app/lib/services/achievement_service.dart` | Fetch achievements from Supabase |
| `flutter_app/lib/services/fcm_service.dart` | Token management + FCM message routing |
| `flutter_app/test/models/achievement_test.dart` | Unit tests for Achievement.fromJson |
| `flutter_app/test/models/leaderboard_entry_test.dart` | Unit tests for updated LeaderboardEntry.fromJson |
| `flutter_app/test/models/follow_up_action_test.dart` | Unit tests for updated FollowUpAction.fromJson |

### Modified Flutter files
| File | Changes |
|---|---|
| `flutter_app/pubspec.yaml` | Add `firebase_core`, `firebase_messaging` |
| `flutter_app/lib/models/leaderboard_entry.dart` | Add `totalPoints` field |
| `flutter_app/lib/models/follow_up_action.dart` | `action`→`actionType`, add `scheduledFollowUpAt`, `outcomeNote` |
| `flutter_app/lib/services/report_service.dart` | Order by `total_points` |
| `flutter_app/lib/services/attendance_service.dart` | Replace `markFollowUpContacted` with `saveFollowUpAction` |
| `flutter_app/lib/core/notifications.dart` | Add FCM init; remove birthday/anniversary local methods |
| `flutter_app/lib/features/home/home_screen.dart` | Remove client birthday check; update follow-up dialog |
| `flutter_app/lib/main.dart` | Add Firebase.initializeApp() + FcmService.initialize() |

---

## Phase 1 — Points System

### Task 1: Create points_ledger table and trigger

**Files:**
- Create: `supabase/migrations/20260424000000_create_points_ledger.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260424000000_create_points_ledger.sql
-- Append-only ledger: one row per (member, session) attendance point.
-- A DB trigger fires on clock_ins INSERT/UPDATE to award the point.

CREATE TABLE IF NOT EXISTS public.points_ledger (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id   UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  session_id  UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  points      INT NOT NULL DEFAULT 1,
  reason      TEXT NOT NULL DEFAULT 'attendance',
  awarded_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (member_id, session_id)
);

CREATE INDEX IF NOT EXISTS points_ledger_member_idx
  ON public.points_ledger (member_id);

ALTER TABLE public.points_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY points_ledger_authenticated
  ON public.points_ledger FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY points_ledger_anon
  ON public.points_ledger FOR ALL TO anon
  USING (true) WITH CHECK (true);

-- Trigger function: insert 1 point when a clock_in becomes 'present'
CREATE OR REPLACE FUNCTION public.award_attendance_point()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'present' THEN
    INSERT INTO public.points_ledger (member_id, session_id, points, reason)
    VALUES (NEW.member_id, NEW.session_id, 1, 'attendance')
    ON CONFLICT (member_id, session_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fire on INSERT and on UPDATE (e.g. absent → present)
DROP TRIGGER IF EXISTS trigger_award_attendance_point ON public.clock_ins;
CREATE TRIGGER trigger_award_attendance_point
  AFTER INSERT OR UPDATE OF status ON public.clock_ins
  FOR EACH ROW EXECUTE FUNCTION public.award_attendance_point();
```

- [ ] **Step 2: Apply migration to local Supabase**

```bash
cd /Users/user/Desktop/bobby/Guest-Welcome-attendance-app
supabase db reset
# or if you don't want to reset:
supabase migration up
```

Expected: migration runs without error.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260424000000_create_points_ledger.sql
git commit -m "feat(db): add points_ledger table with attendance trigger"
```

---

### Task 2: Update leaderboard views to use total_points

**Files:**
- Create: `supabase/migrations/20260424000001_update_leaderboard_views.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260424000001_update_leaderboard_views.sql
-- Replace present_count ranking with total_points from points_ledger.

DROP VIEW IF EXISTS public.monthly_leaderboard;
DROP VIEW IF EXISTS public.yearly_leaderboard;

CREATE VIEW public.monthly_leaderboard AS
SELECT
  to_char(s.date, 'YYYY-MM') AS year_month,
  m.id                        AS member_id,
  m.full_name,
  m.team,
  m.offline_code,
  COALESCE(SUM(pl.points), 0)::INT AS present_count,
  COALESCE(SUM(pl.points), 0)::INT AS total_points
FROM public.members m
LEFT JOIN public.points_ledger pl ON pl.member_id = m.id
LEFT JOIN public.sessions s       ON s.id = pl.session_id
GROUP BY to_char(s.date, 'YYYY-MM'), m.id, m.full_name, m.team, m.offline_code;

CREATE VIEW public.yearly_leaderboard AS
SELECT
  to_char(s.date, 'YYYY') AS year,
  m.id                     AS member_id,
  m.full_name,
  m.team,
  m.offline_code,
  COALESCE(SUM(pl.points), 0)::INT AS present_count,
  COALESCE(SUM(pl.points), 0)::INT AS total_points
FROM public.members m
LEFT JOIN public.points_ledger pl ON pl.member_id = m.id
LEFT JOIN public.sessions s       ON s.id = pl.session_id
GROUP BY to_char(s.date, 'YYYY'), m.id, m.full_name, m.team, m.offline_code;
```

> Note: `present_count` is kept as an alias so existing Flutter code reading that column keeps working until Task 3 updates the model.

- [ ] **Step 2: Apply migration**

```bash
supabase migration up
```

Expected: migration runs without error; both views exist.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260424000001_update_leaderboard_views.sql
git commit -m "feat(db): rebuild leaderboard views to rank by total_points"
```

---

### Task 3: Update LeaderboardEntry model

**Files:**
- Modify: `flutter_app/lib/models/leaderboard_entry.dart`
- Create: `flutter_app/test/models/leaderboard_entry_test.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter_app/test/models/leaderboard_entry_test.dart`:

```dart
import 'package:attendance_app/models/leaderboard_entry.dart';
import 'package:attendance_app/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardEntry.fromJson', () {
    final json = {
      'year_month': '2026-04',
      'member_id': 'abc-123',
      'full_name': 'Ada Lovelace',
      'team': 'Team A',
      'offline_code': 'OFF1',
      'present_count': 8,
      'total_points': 8,
    };

    test('parses totalPoints from total_points', () {
      final entry = LeaderboardEntry.fromJson(json, rank: 1);
      expect(entry.totalPoints, 8);
    });

    test('rank is assigned from parameter', () {
      final entry = LeaderboardEntry.fromJson(json, rank: 3);
      expect(entry.rank, 3);
    });

    test('falls back to present_count when total_points is null', () {
      final noPoints = Map<String, dynamic>.from(json)
        ..remove('total_points');
      final entry = LeaderboardEntry.fromJson(noPoints, rank: 1);
      expect(entry.totalPoints, 8); // falls back to present_count
    });
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd flutter_app
flutter test test/models/leaderboard_entry_test.dart
```

Expected: FAIL — `The getter 'totalPoints' isn't defined`.

- [ ] **Step 3: Update LeaderboardEntry model**

Replace the entire content of `flutter_app/lib/models/leaderboard_entry.dart`:

```dart
// lib/models/leaderboard_entry.dart
import 'enums.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.memberId,
    required this.memberName,
    required this.team,
    required this.offlineCode,
    required this.presentCount,
    required this.totalPoints,
    required this.yearMonth,
  });

  final int rank;
  final String memberId;
  final String memberName;
  final Team team;
  final String offlineCode;
  final int presentCount;
  final int totalPoints;

  /// Format: "YYYY-MM"
  final String yearMonth;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json,
      {int rank = 0}) {
    final presentCount =
        (json['present_count'] as num?)?.toInt() ?? 0;
    return LeaderboardEntry(
      rank: rank,
      memberId: json['member_id'] as String,
      memberName: json['full_name'] as String,
      team: Team.fromValue((json['team'] as String?) ?? 'None'),
      offlineCode: json['offline_code'] as String,
      presentCount: presentCount,
      totalPoints:
          (json['total_points'] as num?)?.toInt() ?? presentCount,
      yearMonth: json['year_month'] as String,
    );
  }
}
```

- [ ] **Step 4: Run test — confirm it passes**

```bash
flutter test test/models/leaderboard_entry_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/leaderboard_entry.dart test/models/leaderboard_entry_test.dart
git commit -m "feat(flutter): add totalPoints to LeaderboardEntry model"
```

---

### Task 4: Update ReportService to order by total_points

**Files:**
- Modify: `flutter_app/lib/services/report_service.dart`

- [ ] **Step 1: Update getMonthlyLeaderboard ordering**

In `flutter_app/lib/services/report_service.dart`, find the `getMonthlyLeaderboard` method and change the order clause from `present_count` to `total_points`:

```dart
  Future<List<LeaderboardEntry>> getMonthlyLeaderboard(
      String yearMonth) async {
    AppLogger.info(_tag, 'getMonthlyLeaderboard($yearMonth)');
    try {
      final data = await _client
          .from('monthly_leaderboard')
          .select()
          .eq('year_month', yearMonth)
          .order('total_points', ascending: false)
          .order('full_name', ascending: true);

      final entries = (data as List)
          .asMap()
          .entries
          .map((e) => LeaderboardEntry.fromJson(e.value, rank: e.key + 1))
          .toList();
      AppLogger.info(_tag,
          'getMonthlyLeaderboard($yearMonth) → ${entries.length} entries');
      return entries;
    } catch (e, stack) {
      AppLogger.error(
          _tag, 'getMonthlyLeaderboard($yearMonth) failed', e, stack);
      rethrow;
    }
  }
```

- [ ] **Step 2: Update getYearlyLeaderboard ordering (if it exists)**

Find `getYearlyLeaderboard` in the same file and change `.order('present_count'...)` to `.order('total_points'...)`.

- [ ] **Step 3: Verify app compiles**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd ..
git add flutter_app/lib/services/report_service.dart
git commit -m "feat(flutter): order leaderboard by total_points"
```

---

## Phase 2 — Achievements System

### Task 5: Create member_achievements table and streak function

**Files:**
- Create: `supabase/migrations/20260424000002_create_member_achievements.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260424000002_create_member_achievements.sql

CREATE TABLE IF NOT EXISTS public.member_achievements (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id        UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  achievement_type TEXT NOT NULL,
  achieved_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  metadata         JSONB NULL,
  CONSTRAINT member_achievements_type_check CHECK (
    achievement_type IN (
      'streak_4', 'streak_8', 'streak_16',
      'tier_bronze', 'tier_silver', 'tier_gold', 'tier_platinum',
      'perfect_month',
      'anniversary_1yr', 'anniversary_2yr'
    )
  )
);

-- Unique per type per member, EXCEPT perfect_month which is unique per year-month
CREATE UNIQUE INDEX member_achievements_unique_type
  ON public.member_achievements (member_id, achievement_type)
  WHERE achievement_type != 'perfect_month';

CREATE UNIQUE INDEX member_achievements_unique_perfect_month
  ON public.member_achievements (member_id, achievement_type, (metadata->>'year_month'))
  WHERE achievement_type = 'perfect_month';

CREATE INDEX member_achievements_member_idx
  ON public.member_achievements (member_id, achieved_at DESC);

ALTER TABLE public.member_achievements ENABLE ROW LEVEL SECURITY;

CREATE POLICY member_achievements_authenticated
  ON public.member_achievements FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY member_achievements_anon
  ON public.member_achievements FOR ALL TO anon
  USING (true) WITH CHECK (true);

-- Returns the current consecutive Sunday streak for a member.
-- Counts backwards from the most recent Sunday session.
CREATE OR REPLACE FUNCTION public.get_member_streak(p_member_id UUID)
RETURNS INT AS $$
DECLARE
  v_streak INT := 0;
  v_row    RECORD;
BEGIN
  FOR v_row IN
    SELECT ci.status
    FROM public.clock_ins ci
    JOIN public.sessions s ON s.id = ci.session_id
    WHERE ci.member_id = p_member_id
      AND EXTRACT(DOW FROM s.date) = 0  -- Sunday only
    ORDER BY s.date DESC
  LOOP
    IF v_row.status = 'present' THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;
  RETURN v_streak;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
```

- [ ] **Step 2: Apply migration**

```bash
supabase migration up
```

Expected: table and function created without error.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260424000002_create_member_achievements.sql
git commit -m "feat(db): add member_achievements table and get_member_streak function"
```

---

### Task 6: Create evaluate-achievements Edge Function

**Files:**
- Create: `supabase/functions/evaluate-achievements/index.ts`

- [ ] **Step 1: Write the Edge Function**

```typescript
// supabase/functions/evaluate-achievements/index.ts
//
// Idempotently evaluates and unlocks achievements for all members.
// Safe to re-run — will not create duplicates.
// Called: nightly via Dashboard cron + manually after a session closes.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const TIER_THRESHOLDS: Record<string, number> = {
  tier_bronze: 10,
  tier_silver: 25,
  tier_gold: 50,
  tier_platinum: 100,
}

const STREAK_THRESHOLDS: Record<string, number> = {
  streak_4: 4,
  streak_8: 8,
  streak_16: 16,
}

Deno.serve(async () => {
  try {
    const { data: members, error: membersErr } = await supabase
      .from('members')
      .select('id, created_at')

    if (membersErr) throw membersErr

    let unlocked = 0

    for (const member of members ?? []) {
      // ── Total points ────────────────────────────────────────────────
      const { data: ledger } = await supabase
        .from('points_ledger')
        .select('points')
        .eq('member_id', member.id)

      const totalPoints = (ledger ?? []).reduce(
        (sum: number, r: { points: number }) => sum + r.points, 0
      )

      for (const [type, threshold] of Object.entries(TIER_THRESHOLDS)) {
        if (totalPoints >= threshold) {
          const { error } = await supabase
            .from('member_achievements')
            .insert({ member_id: member.id, achievement_type: type })
            .onConflict('member_id, achievement_type')
            .ignore()
          if (!error) unlocked++
        }
      }

      // ── Streak ──────────────────────────────────────────────────────
      const { data: streakData } = await supabase
        .rpc('get_member_streak', { p_member_id: member.id })

      const streak = (streakData as number) ?? 0

      for (const [type, threshold] of Object.entries(STREAK_THRESHOLDS)) {
        if (streak >= threshold) {
          const { error } = await supabase
            .from('member_achievements')
            .insert({ member_id: member.id, achievement_type: type })
            .onConflict('member_id, achievement_type')
            .ignore()
          if (!error) unlocked++
        }
      }

      // ── Perfect month ────────────────────────────────────────────────
      // Find months where sessions existed and member attended all of them
      const { data: monthlyData } = await supabase
        .from('sessions')
        .select('id, date')
        .order('date')

      const sessionsByMonth: Record<string, string[]> = {}
      for (const s of monthlyData ?? []) {
        const ym = s.date.slice(0, 7) // "YYYY-MM"
        sessionsByMonth[ym] = sessionsByMonth[ym] ?? []
        sessionsByMonth[ym].push(s.id)
      }

      for (const [ym, sessionIds] of Object.entries(sessionsByMonth)) {
        const { data: attended } = await supabase
          .from('clock_ins')
          .select('session_id')
          .eq('member_id', member.id)
          .eq('status', 'present')
          .in('session_id', sessionIds)

        if ((attended ?? []).length === sessionIds.length && sessionIds.length > 0) {
          const { error } = await supabase
            .from('member_achievements')
            .insert({
              member_id: member.id,
              achievement_type: 'perfect_month',
              metadata: { year_month: ym },
            })
            .onConflict('member_id, achievement_type, (metadata->>\'year_month\')')
            .ignore()
          if (!error) unlocked++
        }
      }

      // ── Church anniversary ───────────────────────────────────────────
      const joinDate = new Date(member.created_at)
      const now = new Date()
      const yearsAttending = now.getFullYear() - joinDate.getFullYear()

      for (const years of [1, 2]) {
        if (yearsAttending >= years) {
          const type = `anniversary_${years}yr`
          const { error } = await supabase
            .from('member_achievements')
            .insert({ member_id: member.id, achievement_type: type })
            .onConflict('member_id, achievement_type')
            .ignore()
          if (!error) unlocked++
        }
      }
    }

    return new Response(
      JSON.stringify({ success: true, unlocked }),
      { headers: { 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    console.error('evaluate-achievements error:', err)
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
```

- [ ] **Step 2: Deploy the function**

```bash
supabase functions deploy evaluate-achievements
```

Expected: `Deployed evaluate-achievements`

- [ ] **Step 3: Test the function manually**

```bash
supabase functions invoke evaluate-achievements --no-verify-jwt
```

Expected: `{"success":true,"unlocked":<number>}`

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/evaluate-achievements/
git commit -m "feat(edge): add evaluate-achievements function"
```

---

### Task 7: Achievement model

**Files:**
- Create: `flutter_app/lib/models/achievement.dart`
- Create: `flutter_app/test/models/achievement_test.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter_app/test/models/achievement_test.dart`:

```dart
import 'package:attendance_app/models/achievement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Achievement.fromJson', () {
    test('parses all required fields', () {
      final json = {
        'id': 'ach-001',
        'member_id': 'mem-001',
        'achievement_type': 'tier_bronze',
        'achieved_at': '2026-04-01T00:00:00.000Z',
        'metadata': null,
      };
      final a = Achievement.fromJson(json);
      expect(a.id, 'ach-001');
      expect(a.memberId, 'mem-001');
      expect(a.achievementType, AchievementType.tierBronze);
      expect(a.achievedAt, DateTime.parse('2026-04-01T00:00:00.000Z'));
      expect(a.metadata, isNull);
    });

    test('parses metadata when present', () {
      final json = {
        'id': 'ach-002',
        'member_id': 'mem-001',
        'achievement_type': 'perfect_month',
        'achieved_at': '2026-04-01T00:00:00.000Z',
        'metadata': {'year_month': '2026-03'},
      };
      final a = Achievement.fromJson(json);
      expect(a.achievementType, AchievementType.perfectMonth);
      expect(a.metadata?['year_month'], '2026-03');
    });

    test('label returns human-readable string', () {
      expect(Achievement.fromJson({
        'id': 'x', 'member_id': 'x',
        'achievement_type': 'streak_4',
        'achieved_at': '2026-01-01T00:00:00Z',
        'metadata': null,
      }).label, '4-Week Streak');
    });
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd flutter_app
flutter test test/models/achievement_test.dart
```

Expected: FAIL — `Achievement` not defined.

- [ ] **Step 3: Create Achievement model**

Create `flutter_app/lib/models/achievement.dart`:

```dart
// lib/models/achievement.dart

enum AchievementType {
  streak4,
  streak8,
  streak16,
  tierBronze,
  tierSilver,
  tierGold,
  tierPlatinum,
  perfectMonth,
  anniversary1yr,
  anniversary2yr;

  static AchievementType fromString(String value) {
    return switch (value) {
      'streak_4'       => streak4,
      'streak_8'       => streak8,
      'streak_16'      => streak16,
      'tier_bronze'    => tierBronze,
      'tier_silver'    => tierSilver,
      'tier_gold'      => tierGold,
      'tier_platinum'  => tierPlatinum,
      'perfect_month'  => perfectMonth,
      'anniversary_1yr' => anniversary1yr,
      'anniversary_2yr' => anniversary2yr,
      _               => throw ArgumentError('Unknown achievement type: $value'),
    };
  }
}

class Achievement {
  const Achievement({
    required this.id,
    required this.memberId,
    required this.achievementType,
    required this.achievedAt,
    this.metadata,
  });

  final String id;
  final String memberId;
  final AchievementType achievementType;
  final DateTime achievedAt;
  final Map<String, dynamic>? metadata;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      achievementType:
          AchievementType.fromString(json['achievement_type'] as String),
      achievedAt: DateTime.parse(json['achieved_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  String get label => switch (achievementType) {
    AchievementType.streak4        => '4-Week Streak',
    AchievementType.streak8        => '8-Week Streak',
    AchievementType.streak16       => '16-Week Streak',
    AchievementType.tierBronze     => 'Bronze Member',
    AchievementType.tierSilver     => 'Silver Member',
    AchievementType.tierGold       => 'Gold Member',
    AchievementType.tierPlatinum   => 'Platinum Member',
    AchievementType.perfectMonth   => 'Perfect Month',
    AchievementType.anniversary1yr => '1-Year Anniversary',
    AchievementType.anniversary2yr => '2-Year Anniversary',
  };

  String get emoji => switch (achievementType) {
    AchievementType.streak4        => '🔥',
    AchievementType.streak8        => '🔥🔥',
    AchievementType.streak16       => '🔥🔥🔥',
    AchievementType.tierBronze     => '🥉',
    AchievementType.tierSilver     => '🥈',
    AchievementType.tierGold       => '🥇',
    AchievementType.tierPlatinum   => '💎',
    AchievementType.perfectMonth   => '⭐',
    AchievementType.anniversary1yr => '🎖️',
    AchievementType.anniversary2yr => '🏆',
  };
}
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
flutter test test/models/achievement_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/achievement.dart test/models/achievement_test.dart
git commit -m "feat(flutter): add Achievement model with AchievementType enum"
```

---

### Task 8: AchievementService

**Files:**
- Create: `flutter_app/lib/services/achievement_service.dart`

- [ ] **Step 1: Create the service**

```dart
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
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/services/achievement_service.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/services/achievement_service.dart
git commit -m "feat(flutter): add AchievementService"
```

---

### Task 9: Show achievements on member detail screen

**Files:**
- Modify: `flutter_app/lib/features/members/member_detail_screen.dart`

- [ ] **Step 1: Add achievements provider at top of member_detail_screen.dart**

Find the file and add a provider near the top (after existing providers):

```dart
// Add this import at the top of the file
import '../../models/achievement.dart';
import '../../services/achievement_service.dart';

// Add this provider near the other providers in the file
final _memberAchievementsProvider =
    FutureProvider.family<List<Achievement>, String>((ref, memberId) {
  return ref.read(achievementServiceProvider).getAchievementsForMember(memberId);
});
```

- [ ] **Step 2: Add the achievements section widget**

Add this widget class at the bottom of `member_detail_screen.dart` (before the final closing brace of the file):

```dart
class _AchievementsSection extends ConsumerWidget {
  const _AchievementsSection({required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievementsAsync =
        ref.watch(_memberAchievementsProvider(memberId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return achievementsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (achievements) {
        if (achievements.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Achievements',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Colors.white
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: achievements
                    .map((a) => Chip(
                          avatar: Text(a.emoji,
                              style: const TextStyle(fontSize: 14)),
                          label: Text(a.label,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 3: Insert `_AchievementsSection` into the member detail layout**

In the `build` method, find where the attendance history or bottom section is rendered and add `_AchievementsSection(memberId: widget.memberId)` (or `memberId: memberId` depending on how the ID is accessed in that screen). Add it above or below the attendance history section.

- [ ] **Step 4: Verify it compiles**

```bash
flutter analyze lib/features/members/member_detail_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/members/member_detail_screen.dart
git commit -m "feat(flutter): show achievements on member detail screen"
```

---

## Phase 3 — Follow-Up Extension

### Task 10: Extend follow_up_actions table

**Files:**
- Create: `supabase/migrations/20260424000003_extend_follow_up_actions.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260424000003_extend_follow_up_actions.sql
-- Rename action → action_type, broaden the CHECK constraint,
-- add scheduled_follow_up_at and outcome_note columns.

-- 1. Rename the column
ALTER TABLE public.member_follow_up_actions
  RENAME COLUMN action TO action_type;

-- 2. Drop old single-value CHECK constraint
ALTER TABLE public.member_follow_up_actions
  DROP CONSTRAINT IF EXISTS member_follow_up_actions_action_check;

-- 3. Add new CHECK with all allowed values
ALTER TABLE public.member_follow_up_actions
  ADD CONSTRAINT member_follow_up_actions_action_type_check
  CHECK (action_type IN (
    'contacted',
    'not_reachable',
    'returned',
    'transferred_out',
    'needs_visit'
  ));

-- 4. Add new columns
ALTER TABLE public.member_follow_up_actions
  ADD COLUMN IF NOT EXISTS scheduled_follow_up_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS outcome_note TEXT NULL;

-- 5. Index for daily reminder query
CREATE INDEX IF NOT EXISTS member_follow_up_actions_scheduled_idx
  ON public.member_follow_up_actions (scheduled_follow_up_at)
  WHERE scheduled_follow_up_at IS NOT NULL;
```

- [ ] **Step 2: Apply migration**

```bash
supabase migration up
```

Expected: runs without error.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260424000003_extend_follow_up_actions.sql
git commit -m "feat(db): extend member_follow_up_actions with action_type and scheduling"
```

---

### Task 11: Update FollowUpAction model

**Files:**
- Modify: `flutter_app/lib/models/follow_up_action.dart`
- Create: `flutter_app/test/models/follow_up_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter_app/test/models/follow_up_action_test.dart`:

```dart
import 'package:attendance_app/models/follow_up_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FollowUpAction.fromJson', () {
    test('parses action_type and new optional fields', () {
      final json = {
        'id': 'fa-001',
        'member_id': 'mem-001',
        'action_type': 'not_reachable',
        'created_by_staff_id': 'staff-001',
        'created_at': '2026-04-10T10:00:00.000Z',
        'note': 'Called twice',
        'scheduled_follow_up_at': '2026-04-17T10:00:00.000Z',
        'outcome_note': 'Will try again next week',
      };
      final fa = FollowUpAction.fromJson(json);
      expect(fa.actionType, 'not_reachable');
      expect(fa.scheduledFollowUpAt,
          DateTime.parse('2026-04-17T10:00:00.000Z'));
      expect(fa.outcomeNote, 'Will try again next week');
    });

    test('nullable fields default to null', () {
      final json = {
        'id': 'fa-002',
        'member_id': 'mem-001',
        'action_type': 'contacted',
        'created_by_staff_id': 'staff-001',
        'created_at': '2026-04-10T10:00:00.000Z',
        'note': null,
        'scheduled_follow_up_at': null,
        'outcome_note': null,
      };
      final fa = FollowUpAction.fromJson(json);
      expect(fa.scheduledFollowUpAt, isNull);
      expect(fa.outcomeNote, isNull);
    });
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
flutter test test/models/follow_up_action_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Rewrite FollowUpAction model**

Replace the entire content of `flutter_app/lib/models/follow_up_action.dart`:

```dart
// lib/models/follow_up_action.dart

class FollowUpAction {
  const FollowUpAction({
    required this.id,
    required this.memberId,
    required this.actionType,
    required this.createdByStaffId,
    required this.createdAt,
    this.note,
    this.scheduledFollowUpAt,
    this.outcomeNote,
  });

  final String id;
  final String memberId;
  final String actionType;
  final String createdByStaffId;
  final DateTime createdAt;
  final String? note;
  final DateTime? scheduledFollowUpAt;
  final String? outcomeNote;

  factory FollowUpAction.fromJson(Map<String, dynamic> json) {
    return FollowUpAction(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      actionType: json['action_type'] as String,
      createdByStaffId: json['created_by_staff_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      note: json['note'] as String?,
      scheduledFollowUpAt: json['scheduled_follow_up_at'] == null
          ? null
          : DateTime.parse(json['scheduled_follow_up_at'] as String),
      outcomeNote: json['outcome_note'] as String?,
    );
  }
}
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
flutter test test/models/follow_up_action_test.dart
```

Expected: All 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/follow_up_action.dart test/models/follow_up_action_test.dart
git commit -m "feat(flutter): update FollowUpAction model with action_type and scheduling fields"
```

---

### Task 12: Update AttendanceService follow-up method

**Files:**
- Modify: `flutter_app/lib/services/attendance_service.dart`

- [ ] **Step 1: Replace markFollowUpContacted with saveFollowUpAction**

Find `markFollowUpContacted` at line ~379 in `attendance_service.dart` and replace the entire method:

```dart
  /// Records a follow-up action for an absent member.
  /// [actionType] must be one of: contacted, not_reachable, returned,
  /// transferred_out, needs_visit.
  Future<void> saveFollowUpAction({
    required String memberId,
    required String staffId,
    required String actionType,
    String? note,
    DateTime? scheduledFollowUpAt,
    String? outcomeNote,
  }) async {
    AppLogger.info(
      _tag,
      'saveFollowUpAction(member=$memberId, type=$actionType)',
    );
    try {
      await _client.from(_followUpActionsTable).insert({
        'member_id': memberId,
        'action_type': actionType,
        'created_by_staff_id': staffId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (scheduledFollowUpAt != null)
          'scheduled_follow_up_at': scheduledFollowUpAt.toUtc().toIso8601String(),
        if (outcomeNote != null && outcomeNote.trim().isNotEmpty)
          'outcome_note': outcomeNote.trim(),
      });
      AppLogger.info(_tag, 'saveFollowUpAction → saved');
    } catch (e, s) {
      AppLogger.error(_tag, 'saveFollowUpAction failed', e, s);
      rethrow;
    }
  }
```

- [ ] **Step 2: Fix the _getLatestFollowUpActions query**

Find `_getLatestFollowUpActions` (around line 459) and update the filter that reads the `action` field to use `action_type`. The method returns a `Map<String, FollowUpAction>` — the `FollowUpAction.fromJson` call will now use the renamed field automatically.

- [ ] **Step 3: Fix compile errors**

Run:
```bash
flutter analyze lib/services/attendance_service.dart
```

Fix any remaining references to `markFollowUpContacted` or the old `action` field.

- [ ] **Step 4: Commit**

```bash
git add lib/services/attendance_service.dart
git commit -m "feat(flutter): replace markFollowUpContacted with saveFollowUpAction"
```

---

### Task 13: Update follow-up dialog in home_screen.dart

**Files:**
- Modify: `flutter_app/lib/features/home/home_screen.dart`

- [ ] **Step 1: Replace the `_markContacted` method**

Find `_markContacted` around line 1023 and replace the entire method:

```dart
  Future<void> _markContacted(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final staff = currentStaff;
    if (staff == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You need to be signed in to log a follow-up.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    // Show the enhanced follow-up dialog
    final result = await _showFollowUpDialog(context, member);
    if (result == null || !context.mounted) return;

    try {
      await ref.read(attendanceServiceProvider).saveFollowUpAction(
            memberId: member.id,
            staffId: staff.id,
            actionType: result.actionType,
            note: result.note,
            scheduledFollowUpAt: result.scheduledFollowUpAt,
            outcomeNote: result.outcomeNote,
          );
      ref.invalidate(_absentMembersProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Follow-up logged for ${member.fullName}.',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save follow-up: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
```

- [ ] **Step 2: Add the follow-up dialog and result class**

Add these two classes at the bottom of `home_screen.dart` (before the final `}`):

```dart
// ── Follow-up dialog data ─────────────────────────────────────────────────────

class _FollowUpResult {
  const _FollowUpResult({
    required this.actionType,
    this.note,
    this.scheduledFollowUpAt,
    this.outcomeNote,
  });
  final String actionType;
  final String? note;
  final DateTime? scheduledFollowUpAt;
  final String? outcomeNote;
}

Future<_FollowUpResult?> _showFollowUpDialog(
  BuildContext context,
  Member member,
) async {
  String selectedAction = 'contacted';
  DateTime? scheduledDate;
  final noteCtrl = TextEditingController();
  final outcomeCtrl = TextEditingController();

  const actions = [
    ('contacted', 'Contacted'),
    ('not_reachable', 'Not Reachable'),
    ('returned', 'Returned to Church'),
    ('transferred_out', 'Transferred Out'),
    ('needs_visit', 'Needs a Visit'),
  ];

  return showDialog<_FollowUpResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Follow-up: ${member.fullName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Action taken:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedAction,
                items: actions
                    .map((a) => DropdownMenuItem(
                          value: a.$1,
                          child: Text(a.$2),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => selectedAction = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: outcomeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Outcome note (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Schedule next follow-up:',
                      style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate:
                            DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => scheduledDate = picked);
                      }
                    },
                    child: Text(
                      scheduledDate == null
                          ? 'Pick date'
                          : '${scheduledDate!.day}/${scheduledDate!.month}/${scheduledDate!.year}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_FollowUpResult(
              actionType: selectedAction,
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              scheduledFollowUpAt: scheduledDate,
              outcomeNote: outcomeCtrl.text.trim().isEmpty
                  ? null
                  : outcomeCtrl.text.trim(),
            )),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3: Verify no compile errors**

```bash
flutter analyze lib/features/home/home_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "feat(flutter): enhanced follow-up dialog with action type, scheduling, and notes"
```

---

## Phase 4 — FCM Infrastructure

### Task 14: Firebase project setup (manual steps)

These steps must be done by a human in the browser and Xcode/Android Studio.

- [ ] **Step 1: Create Firebase project**
  1. Go to [console.firebase.google.com](https://console.firebase.google.com)
  2. Click "Add project" → name it (e.g. `guest-welcome-attendance`)
  3. Disable Google Analytics (not needed) → Create project

- [ ] **Step 2: Add Android app**
  1. In Firebase project → Add app → Android
  2. Android package name: `com.example.attendance_app` (check `flutter_app/android/app/build.gradle` for the actual `applicationId`)
  3. Download `google-services.json`
  4. Place it at `flutter_app/android/app/google-services.json`

- [ ] **Step 3: Add iOS app**
  1. In Firebase project → Add app → iOS
  2. iOS bundle ID: check `flutter_app/ios/Runner.xcodeproj` or `flutter_app/ios/Runner/Info.plist` for `CFBundleIdentifier`
  3. Download `GoogleService-Info.plist`
  4. Place it at `flutter_app/ios/Runner/GoogleService-Info.plist`

- [ ] **Step 4: Enable Cloud Messaging**
  1. Firebase console → Project Settings → Cloud Messaging
  2. Ensure the API is enabled

- [ ] **Step 5: Store FCM server key as Supabase secret**

```bash
# Get the service account JSON from Firebase: Project Settings → Service Accounts → Generate new private key
# Then set it as a Supabase secret:
supabase secrets set FCM_SERVICE_ACCOUNT_JSON='<paste the entire JSON here>'
supabase secrets set FCM_PROJECT_ID='<your-firebase-project-id>'
```

---

### Task 15: Add Firebase packages to pubspec.yaml

**Files:**
- Modify: `flutter_app/pubspec.yaml`

- [ ] **Step 1: Add dependencies**

In `flutter_app/pubspec.yaml`, add under `dependencies:`:

```yaml
  # Firebase push notifications
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
```

- [ ] **Step 2: Install packages**

```bash
cd flutter_app
flutter pub get
```

Expected: packages resolve without conflict.

- [ ] **Step 3: Android: apply google-services plugin**

In `flutter_app/android/build.gradle` (project-level), add to `buildscript.dependencies`:
```groovy
classpath 'com.google.gms:google-services:4.4.2'
```

In `flutter_app/android/app/build.gradle` (app-level), add at the bottom:
```groovy
apply plugin: 'com.google.gms.google-services'
```

- [ ] **Step 4: Verify Android build compiles**

```bash
flutter build apk --debug
```

Expected: builds without error.

- [ ] **Step 5: Commit**

```bash
cd ..
git add flutter_app/pubspec.yaml flutter_app/pubspec.lock \
        flutter_app/android/build.gradle flutter_app/android/app/build.gradle
git commit -m "feat(flutter): add firebase_core and firebase_messaging packages"
```

---

### Task 16: Create device_tokens table

**Files:**
- Create: `supabase/migrations/20260424000004_create_device_tokens.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260424000004_create_device_tokens.sql
-- Stores FCM device tokens per staff member.
-- Used by Edge Functions to send push notifications to all active staff devices.

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id   UUID NOT NULL REFERENCES public.staff_users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL UNIQUE,
  platform   TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS device_tokens_staff_idx
  ON public.device_tokens (staff_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY device_tokens_authenticated
  ON public.device_tokens FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY device_tokens_anon
  ON public.device_tokens FOR ALL TO anon
  USING (true) WITH CHECK (true);
```

- [ ] **Step 2: Apply migration**

```bash
supabase migration up
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260424000004_create_device_tokens.sql
git commit -m "feat(db): add device_tokens table for FCM"
```

---

### Task 17: Create FcmService (Flutter token management)

**Files:**
- Create: `flutter_app/lib/services/fcm_service.dart`

- [ ] **Step 1: Create the service**

```dart
// lib/services/fcm_service.dart
//
// Manages FCM device token registration and message routing.
// Call FcmService.initialize() once in main.dart after Firebase.initializeApp().

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logger.dart';

class FcmService {
  FcmService._();

  static const _tag = 'FcmService';
  static const _tokensTable = 'device_tokens';

  static Future<void> initialize(String staffId) async {
    // Request permission
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    AppLogger.info(_tag,
        'FCM permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      AppLogger.warn(_tag, 'FCM permission denied — push will not work');
      return;
    }

    // Get and register current token
    final token = await messaging.getToken();
    if (token != null) {
      await _upsertToken(staffId, token);
    }

    // Keep token fresh when FCM rotates it
    messaging.onTokenRefresh.listen((newToken) {
      _upsertToken(staffId, newToken);
    });
  }

  static Future<void> deleteToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    try {
      await Supabase.instance.client
          .from(_tokensTable)
          .delete()
          .eq('token', token);
      await FirebaseMessaging.instance.deleteToken();
      AppLogger.info(_tag, 'FCM token deleted');
    } catch (e, stack) {
      AppLogger.error(_tag, 'deleteToken failed', e, stack);
    }
  }

  static Future<void> _upsertToken(String staffId, String token) async {
    final platform = Platform.isAndroid ? 'android' : 'ios';
    try {
      await Supabase.instance.client.from(_tokensTable).upsert(
        {
          'staff_id': staffId,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );
      AppLogger.info(_tag, 'FCM token upserted (platform: $platform)');
    } catch (e, stack) {
      AppLogger.error(_tag, '_upsertToken failed', e, stack);
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/services/fcm_service.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/services/fcm_service.dart
git commit -m "feat(flutter): add FcmService for token management"
```

---

### Task 18: Initialize Firebase in main.dart and call FcmService

**Files:**
- Modify: `flutter_app/lib/main.dart`

- [ ] **Step 1: Read current main.dart**

Read `flutter_app/lib/main.dart` to see exact content before editing.

- [ ] **Step 2: Add Firebase initialization**

Add the following imports at the top of `main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/fcm_service.dart';
```

In the `main()` function, add Firebase init and background message handler **before** `runApp`:

```dart
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background handler must be a top-level function.
  // Deep linking on tap is handled in FcmService.initialize().
  // No action needed here — the notification is already shown by FCM.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  // ... rest of existing init (Supabase, NotificationService, etc.)
  runApp(const ProviderScope(child: AttendanceApp()));
}
```

- [ ] **Step 3: Call FcmService.initialize after staff logs in**

In `flutter_app/lib/features/auth/profile_picker_screen.dart` (or wherever staff login completes), after a staff member is selected/logged in, add:

```dart
// After staff is authenticated and their ID is available:
await FcmService.initialize(staff.id);
```

Find the login success callback in the auth flow and add this call there.

- [ ] **Step 4: Call FcmService.deleteToken on logout**

Find the logout action (likely in `settings_screen.dart` or `auth_service.dart`) and add:

```dart
await FcmService.deleteToken();
```

before the Supabase sign-out call.

- [ ] **Step 5: Verify it compiles**

```bash
flutter analyze lib/main.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/features/auth/ lib/features/settings/
git commit -m "feat(flutter): initialize Firebase and FCM on app start"
```

---

### Task 19: Create send-push Edge Function (FCM wrapper)

**Files:**
- Create: `supabase/functions/send-push/index.ts`

- [ ] **Step 1: Write the Edge Function**

```typescript
// supabase/functions/send-push/index.ts
//
// Shared helper: sends FCM push notifications to a list of device tokens.
// Automatically removes stale tokens from the database.
//
// POST body: { tokens: string[], title: string, body: string, data?: Record<string, string> }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// Returns a short-lived OAuth2 access token for FCM HTTP v1 API
async function getFcmAccessToken(): Promise<string> {
  const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')!
  const sa = JSON.parse(serviceAccountJson)

  const now = Math.floor(Date.now() / 1000)
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = btoa(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))

  // Sign the JWT with the private key using Web Crypto
  const pemKey = sa.private_key as string
  const pemBody = pemKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const privateKey = await crypto.subtle.importKey(
    'pkcs8', keyData.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign']
  )
  const signingInput = `${header}.${payload}`
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', privateKey,
    new TextEncoder().encode(signingInput)
  )
  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  const jwt = `${signingInput}.${sig}`

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const tokenData = await tokenRes.json()
  return tokenData.access_token as string
}

Deno.serve(async (req) => {
  try {
    const { tokens, title, body, data } = await req.json() as {
      tokens: string[]
      title: string
      body: string
      data?: Record<string, string>
    }

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, stale: 0 }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const projectId = Deno.env.get('FCM_PROJECT_ID')!
    const accessToken = await getFcmAccessToken()
    const staleTokens: string[] = []
    let sent = 0

    for (const token of tokens) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body },
              data: data ?? {},
            },
          }),
        }
      )

      if (res.ok) {
        sent++
      } else {
        const err = await res.json()
        const status = err?.error?.status
        if (status === 'UNREGISTERED' || status === 'INVALID_ARGUMENT') {
          staleTokens.push(token)
        } else {
          console.error('FCM send error:', err)
        }
      }
    }

    // Remove stale tokens
    if (staleTokens.length > 0) {
      await supabase.from('device_tokens').delete().in('token', staleTokens)
      console.log(`Removed ${staleTokens.length} stale FCM tokens`)
    }

    return new Response(JSON.stringify({ sent, stale: staleTokens.length }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('send-push error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
```

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy send-push
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/send-push/
git commit -m "feat(edge): add send-push FCM wrapper function"
```

---

## Phase 5 — Birthday & Anniversary Notifications

### Task 20: Create birthday_notification_log table

**Files:**
- Create: `supabase/migrations/20260424000005_create_birthday_notification_log.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260424000005_create_birthday_notification_log.sql
-- Prevents duplicate birthday/anniversary push notifications.

CREATE TABLE IF NOT EXISTS public.birthday_notification_log (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id         UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL CHECK (
    notification_type IN (
      'birthday_eve', 'birthday_morning',
      'anniversary_eve', 'anniversary_morning'
    )
  ),
  sent_at           TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  year              INT NOT NULL,
  UNIQUE (member_id, notification_type, year)
);

ALTER TABLE public.birthday_notification_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY birthday_log_authenticated
  ON public.birthday_notification_log FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY birthday_log_anon
  ON public.birthday_notification_log FOR ALL TO anon
  USING (true) WITH CHECK (true);
```

- [ ] **Step 2: Apply migration**

```bash
supabase migration up
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260424000005_create_birthday_notification_log.sql
git commit -m "feat(db): add birthday_notification_log dedup table"
```

---

### Task 21: Create notify-birthdays Edge Function

**Files:**
- Create: `supabase/functions/notify-birthdays/index.ts`

- [ ] **Step 1: Write the Edge Function**

```typescript
// supabase/functions/notify-birthdays/index.ts
//
// Sends birthday and anniversary push notifications to all staff devices.
// Called twice daily:
//   - 21:00 UTC for "eve" notifications (tomorrow's birthdays)
//   - 06:00 UTC for "morning" notifications (today's birthdays, Lagos ~8 AM)
//
// POST body (optional): { mode: 'eve' | 'morning' }
// If mode is omitted, determined automatically from current UTC hour.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

function toMMDD(date: Date): string {
  const m = String(date.getUTCMonth() + 1).padStart(2, '0')
  const d = String(date.getUTCDate()).padStart(2, '0')
  return `${m}-${d}`
}

async function getAllStaffTokens(): Promise<string[]> {
  const { data } = await supabase.from('device_tokens').select('token')
  return (data ?? []).map((r: { token: string }) => r.token)
}

async function sendPush(tokens: string[], title: string, body: string, data: Record<string, string>) {
  if (tokens.length === 0) return
  await supabase.functions.invoke('send-push', {
    body: { tokens, title, body, data },
  })
}

async function processNotifications(
  mode: 'eve' | 'morning',
  targetDate: Date,
  targetMMDD: string,
  year: number,
  eveSuffix: string,
  morningSuffix: string,
) {
  const typePrefix = mode === 'eve' ? 'eve' : 'morning'
  const tokens = await getAllStaffTokens()
  if (tokens.length === 0) {
    console.log('No staff tokens registered, skipping push')
    return { birthday: 0, anniversary: 0 }
  }

  // Fetch members with matching birthday or anniversary
  const { data: members } = await supabase
    .from('members')
    .select('id, full_name, birthday_md, anniversary_md')

  let birthdayCount = 0
  let anniversaryCount = 0

  for (const m of members ?? []) {
    // Birthday
    if (m.birthday_md === targetMMDD) {
      const notifType = `birthday_${typePrefix}` as const
      const { error } = await supabase
        .from('birthday_notification_log')
        .insert({ member_id: m.id, notification_type: notifType, year })
        .onConflict('member_id, notification_type, year')
        .ignore()

      if (!error) {
        const title = mode === 'eve'
          ? `Birthday tomorrow: ${m.full_name}`
          : `Birthday today: ${m.full_name}`
        const body = mode === 'eve'
          ? `${m.full_name}'s birthday is tomorrow. Prepare to celebrate!`
          : `${m.full_name} is celebrating their birthday today. Reach out!`
        await sendPush(tokens, title, body, {
          type: 'birthday',
          memberId: m.id,
          route: `/members/${m.id}`,
        })
        birthdayCount++
      }
    }

    // Anniversary (wedding)
    if (m.anniversary_md && m.anniversary_md === targetMMDD) {
      const notifType = `anniversary_${typePrefix}` as const
      const { error } = await supabase
        .from('birthday_notification_log')
        .insert({ member_id: m.id, notification_type: notifType, year })
        .onConflict('member_id, notification_type, year')
        .ignore()

      if (!error) {
        const title = mode === 'eve'
          ? `Anniversary tomorrow: ${m.full_name}`
          : `Anniversary today: ${m.full_name}`
        const body = mode === 'eve'
          ? `${m.full_name}'s wedding anniversary is tomorrow.`
          : `${m.full_name} is celebrating their wedding anniversary today!`
        await sendPush(tokens, title, body, {
          type: 'anniversary',
          memberId: m.id,
          route: `/members/${m.id}`,
        })
        anniversaryCount++
      }
    }
  }

  return { birthday: birthdayCount, anniversary: anniversaryCount }
}

Deno.serve(async (req) => {
  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {}
    const now = new Date()
    const utcHour = now.getUTCHours()

    // Auto-detect mode from UTC hour if not provided
    const mode: 'eve' | 'morning' =
      body.mode === 'eve' || body.mode === 'morning'
        ? body.mode
        : utcHour >= 18
        ? 'eve'
        : 'morning'

    const year = now.getUTCFullYear()
    let targetDate: Date

    if (mode === 'eve') {
      targetDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1))
    } else {
      targetDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
    }

    const targetMMDD = toMMDD(targetDate)
    const result = await processNotifications(mode, targetDate, targetMMDD, year, 'eve', 'morning')

    return new Response(JSON.stringify({ success: true, mode, targetMMDD, ...result }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('notify-birthdays error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
```

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy notify-birthdays
```

- [ ] **Step 3: Test manually (eve mode)**

```bash
supabase functions invoke notify-birthdays \
  --body '{"mode":"eve"}' --no-verify-jwt
```

Expected: `{"success":true,"mode":"eve","targetMMDD":"MM-DD","birthday":0,"anniversary":0}` (0 unless tomorrow is someone's birthday)

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/notify-birthdays/
git commit -m "feat(edge): add notify-birthdays function for eve and morning push"
```

---

### Task 22: Remove client-side birthday detection from home_screen.dart

**Files:**
- Modify: `flutter_app/lib/features/home/home_screen.dart`

- [ ] **Step 1: Remove the birthday listener block**

Find and delete lines 154–166 in `home_screen.dart` (the `ref.listen(_membersProvider, ...)` block that loops through members and calls `showBirthdayNotification` / `showAnniversaryNotification`):

```dart
// DELETE THIS ENTIRE BLOCK:
    ref.listen(_membersProvider, (_, next) {
      next.whenData((members) {
        final today = formatMMDD(nowInLagos());
        for (final m in members) {
          if (m.birthdayMD == today) {
            NotificationService.showBirthdayNotification(m);
          }
          if (m.anniversaryMD != null && m.anniversaryMD == today) {
            NotificationService.showAnniversaryNotification(m);
          }
        }
      });
    });
```

- [ ] **Step 2: Remove the import of `formatMMDD` if it is now unused**

Check if `formatMMDD` is used elsewhere in the file. If not, remove its import.

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/features/home/home_screen.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "feat(flutter): remove client-side birthday detection (server-side FCM replaces it)"
```

---

### Task 23: Remove birthday/anniversary methods from NotificationService

**Files:**
- Modify: `flutter_app/lib/core/notifications.dart`

- [ ] **Step 1: Delete the two birthday/anniversary methods**

In `flutter_app/lib/core/notifications.dart`, delete the `showBirthdayNotification` method (lines 58–66) and `showAnniversaryNotification` method (lines 68–77).

Keep:
- `init()`
- `showAbsenceAlert()` (still used as a local notification)
- `showWeeklySessionGenerationNotification()`
- `_details()`

- [ ] **Step 2: Remove the `Member` import if it's now unused**

Check: if `member.dart` import is only used by the deleted methods, remove it.

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/core/notifications.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/core/notifications.dart
git commit -m "feat(flutter): remove birthday local notifications (replaced by FCM)"
```

---

## Phase 6 — Follow-Up Reminders

### Task 24: Create follow-up-reminders Edge Function

**Files:**
- Create: `supabase/functions/follow-up-reminders/index.ts`

- [ ] **Step 1: Write the Edge Function**

```typescript
// supabase/functions/follow-up-reminders/index.ts
//
// Sends FCM push notifications for follow-up actions due today.
// Called daily at 08:00 Lagos time (07:00 UTC).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

Deno.serve(async () => {
  try {
    const now = new Date()
    const todayISO = now.toISOString().slice(0, 10) // "YYYY-MM-DD"

    // Find due follow-up actions (scheduled for today, not yet resolved)
    const { data: dueActions, error } = await supabase
      .from('member_follow_up_actions')
      .select('id, member_id, action_type, members(full_name)')
      .gte('scheduled_follow_up_at', `${todayISO}T00:00:00Z`)
      .lte('scheduled_follow_up_at', `${todayISO}T23:59:59Z`)
      .not('action_type', 'in', '("returned","transferred_out")')

    if (error) throw error

    if (!dueActions || dueActions.length === 0) {
      return new Response(JSON.stringify({ success: true, sent: 0 }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get all staff device tokens
    const { data: tokenRows } = await supabase
      .from('device_tokens')
      .select('token')
    const tokens = (tokenRows ?? []).map((r: { token: string }) => r.token)

    if (tokens.length === 0) {
      return new Response(JSON.stringify({ success: true, sent: 0, reason: 'no_tokens' }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Send one push per due follow-up
    let sent = 0
    for (const action of dueActions) {
      const memberName = (action.members as { full_name: string } | null)?.full_name ?? 'Unknown'
      await supabase.functions.invoke('send-push', {
        body: {
          tokens,
          title: 'Follow-up due today',
          body: `${memberName} — ${action.action_type.replace(/_/g, ' ')}`,
          data: {
            type: 'follow_up',
            memberId: action.member_id,
            route: `/home`,
          },
        },
      })
      sent++
    }

    return new Response(JSON.stringify({ success: true, sent }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('follow-up-reminders error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
```

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy follow-up-reminders
```

- [ ] **Step 3: Test manually**

```bash
supabase functions invoke follow-up-reminders --no-verify-jwt
```

Expected: `{"success":true,"sent":0}` (0 unless follow-ups are due today)

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/follow-up-reminders/
git commit -m "feat(edge): add follow-up-reminders daily push function"
```

---

### Task 25: Schedule cron jobs via Supabase Dashboard

**Files:**
- Create: `supabase/migrations/20260424000006_schedule_notification_crons.sql`

- [ ] **Step 1: Write documentation migration**

```sql
-- supabase/migrations/20260424000006_schedule_notification_crons.sql
--
-- Cron schedules for notification Edge Functions.
-- Applied via Supabase Dashboard → Edge Functions → [function] → Schedules
-- (same approach as generate-sessions per migration 20260421000002)
--
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │ Function              │ Schedule (UTC)         │ Runs at (Lagos)   │
-- ├─────────────────────────────────────────────────────────────────────┤
-- │ notify-birthdays      │ 0 21 * * *  (9 PM UTC) │ 10 PM Lagos (eve) │
-- │ notify-birthdays      │ 0 7  * * *  (7 AM UTC) │ 8 AM Lagos (morn) │
-- │ follow-up-reminders   │ 0 7  * * *  (7 AM UTC) │ 8 AM Lagos        │
-- │ evaluate-achievements │ 0 1  * * *  (1 AM UTC) │ 2 AM Lagos        │
-- └─────────────────────────────────────────────────────────────────────┘
--
-- Steps to apply:
-- 1. Go to Supabase Dashboard → Edge Functions
-- 2. Click notify-birthdays → Schedules tab → Add schedule
--    Cron: "0 21 * * *"  (eve notifications)
--    Body: {"mode":"eve"}
-- 3. Add second schedule for notify-birthdays
--    Cron: "0 7 * * *"   (morning notifications)
--    Body: {"mode":"morning"}
-- 4. Click follow-up-reminders → Schedules tab → Add schedule
--    Cron: "0 7 * * *"
-- 5. Click evaluate-achievements → Schedules tab → Add schedule
--    Cron: "0 1 * * *"

COMMENT ON TABLE public.device_tokens IS
  'FCM device tokens for staff. Used by Edge Functions to push birthday, '
  'anniversary, and follow-up notifications to all active staff devices.';
```

- [ ] **Step 2: Apply migration**

```bash
supabase migration up
```

- [ ] **Step 3: Apply cron schedules in Supabase Dashboard**

Follow the instructions in the migration comment above to add all 4 schedules via the Dashboard.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260424000006_schedule_notification_crons.sql
git commit -m "docs(db): document notification cron schedule setup"
```

---

## Phase 7 — Flutter Push Notification Handling

### Task 26: Handle FCM messages and deep link on tap

**Files:**
- Modify: `flutter_app/lib/services/fcm_service.dart`

- [ ] **Step 1: Add message handlers to FcmService.initialize**

Add the following inside `FcmService.initialize()` after the token setup code:

```dart
    // ── Foreground messages ──────────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.info(_tag, 'FCM foreground message: ${message.notification?.title}');
      // flutter_local_notifications shows an in-app banner
      final n = message.notification;
      if (n != null) {
        NotificationService.showFcmBanner(n.title ?? '', n.body ?? '');
      }
    });

    // ── Notification tap from background ────────────────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data);
    });

    // ── Notification tap when app was terminated ─────────────────────────
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial.data);
    }
```

- [ ] **Step 2: Add _handleNotificationTap and the router reference**

Add these members to `FcmService`:

```dart
  static GoRouter? _router;

  // Call this once after the router is available (e.g. in AttendanceApp.build)
  static void setRouter(GoRouter router) => _router = router;

  static void _handleNotificationTap(Map<String, dynamic> data) {
    final route = data['route'] as String?;
    if (route == null || _router == null) return;
    AppLogger.info(_tag, 'FCM tap → navigating to $route');
    _router!.go(route);
  }
```

Add the import at the top of `fcm_service.dart`:

```dart
import 'package:go_router/go_router.dart';
import '../core/notifications.dart';
```

- [ ] **Step 3: Add showFcmBanner to NotificationService**

In `flutter_app/lib/core/notifications.dart`, add this method:

```dart
  /// Show an in-app banner for a foreground FCM message.
  static Future<void> showFcmBanner(String title, String body) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      _details(),
    );
  }
```

- [ ] **Step 4: Pass router to FcmService in app.dart**

In `flutter_app/lib/app.dart`, inside `_AttendanceAppState.build`, after `final router = ref.watch(routerProvider);` add:

```dart
    FcmService.setRouter(router);
```

Add the import at the top of `app.dart`:

```dart
import 'services/fcm_service.dart';
```

- [ ] **Step 5: Verify it compiles**

```bash
flutter analyze lib/services/fcm_service.dart lib/core/notifications.dart lib/app.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/services/fcm_service.dart lib/core/notifications.dart lib/app.dart
git commit -m "feat(flutter): FCM message handling with deep-link routing on notification tap"
```

---

## Final: Backfill existing clock_ins into points_ledger

### Task 27: Backfill historical attendance data

**Files:**
- Create: `supabase/migrations/20260424000007_backfill_points_ledger.sql`

- [ ] **Step 1: Write the backfill migration**

```sql
-- supabase/migrations/20260424000007_backfill_points_ledger.sql
-- One-time backfill: award 1 point for every existing 'present' clock_in
-- that doesn't yet have an entry in points_ledger.

INSERT INTO public.points_ledger (member_id, session_id, points, reason, awarded_at)
SELECT
  ci.member_id,
  ci.session_id,
  1,
  'attendance',
  ci.clocked_at
FROM public.clock_ins ci
WHERE ci.status = 'present'
ON CONFLICT (member_id, session_id) DO NOTHING;
```

- [ ] **Step 2: Apply migration**

```bash
supabase migration up
```

Expected: rows inserted matching existing present clock_ins.

- [ ] **Step 3: Trigger achievement evaluation for existing members**

```bash
supabase functions invoke evaluate-achievements --no-verify-jwt
```

Expected: achievements unlocked for members who already qualify.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260424000007_backfill_points_ledger.sql
git commit -m "feat(db): backfill points_ledger from existing clock_ins"
```

---

## Definition of Done

- [ ] `points_ledger` auto-populated on every `clock_in` with `status = 'present'`
- [ ] Leaderboard ranks by `total_points` (verified on Reports screen)
- [ ] `member_achievements` populated by `evaluate-achievements` function
- [ ] Achievement badges visible on member detail screen
- [ ] Follow-up dialog shows action type dropdown, scheduling date picker, and notes
- [ ] `member_follow_up_actions.action_type` has 5 possible values in DB
- [ ] `device_tokens` table receives FCM token on staff login
- [ ] Token deleted from `device_tokens` on staff logout
- [ ] `notify-birthdays` function sends push 9 PM eve + 8 AM morning (no duplicate within same year)
- [ ] `follow-up-reminders` sends push for due follow-up actions at 8 AM
- [ ] All 4 cron schedules active in Supabase Dashboard
- [ ] Tapping a notification deep-links to correct screen
- [ ] Client-side birthday detection removed from `home_screen.dart`
