# Systems Overhaul Design
**Date:** 2026-04-24
**Scope:** Points, Achievements, Follow-Up, Birthday, Notifications systems
**Architecture:** Hybrid — Supabase (source of truth) + FCM push + Flutter (display only)
**Key constraint:** Multi-device admin app — all state must live server-side; no device computes or stores authoritative data locally

---

## 1. Points System

### Goal
Award 1 point per attended session, stored in an append-only ledger. Leaderboard ranks by total points.

### Database
- **New table: `points_ledger`**
  - `id` UUID PK
  - `member_id` UUID → members
  - `session_id` UUID → sessions
  - `points` INT DEFAULT 1
  - `reason` TEXT (e.g., `'attendance'`)
  - `awarded_at` TIMESTAMPTZ DEFAULT now()
  - Unique constraint on `(member_id, session_id)` to prevent duplicate awards
- **Trigger:** On `clock_ins` INSERT where `status = 'present'` → insert 1 row into `points_ledger`
- **View update:** `monthly_leaderboard` and `yearly_leaderboard` views updated to JOIN `points_ledger` and rank by `SUM(points)` instead of `COUNT(present)`

### Flutter
- `LeaderboardEntry` model gains `totalPoints` field
- Leaderboard UI displays points alongside rank
- No business logic in Flutter — display only

---

## 2. Achievements System

### Goal
Recognize members for attendance streaks, loyalty tiers, monthly perfect attendance, and church anniversaries. Achievements are computed server-side and displayed in Flutter.

### Achievement Types
| Type | Trigger |
|---|---|
| `streak_4` | 4 consecutive Sundays present |
| `streak_8` | 8 consecutive Sundays present |
| `streak_16` | 16 consecutive Sundays present |
| `tier_bronze` | 10 total points |
| `tier_silver` | 25 total points |
| `tier_gold` | 50 total points |
| `tier_platinum` | 100 total points |
| `perfect_month` | All sessions in a calendar month attended |
| `anniversary_1yr` | 1 year since `join_date` |
| `anniversary_2yr` | 2 years since `join_date` |

### Database
- **New table: `member_achievements`**
  - `id` UUID PK
  - `member_id` UUID → members
  - `achievement_type` TEXT (enum values above)
  - `achieved_at` TIMESTAMPTZ DEFAULT now()
  - `metadata` JSONB (e.g., streak count, month achieved)
  - Unique constraint on `(member_id, achievement_type)` — no duplicates (tiers are one-time unlocks)
  - Exception: `perfect_month` uses `(member_id, achievement_type, metadata->>'year_month')` as unique key

### Computation
- Supabase Edge Function `evaluate_achievements` runs nightly AND is called after each clock-in batch
- Checks each member against all achievement conditions
- Inserts only newly unlocked achievements (idempotent — safe to re-run)

### Streak Logic
- Query `clock_ins` JOIN `sessions` ordered by `session_date DESC` per member
- Walk backwards: count consecutive `present` Sundays; reset to 0 on any non-present Sunday
- Award streak achievements at thresholds 4 / 8 / 16

### Flutter
- New `Achievement` model: `id`, `memberId`, `achievementType`, `achievedAt`
- Member profile screen shows earned badges with date
- Leaderboard shows current tier badge next to member name

---

## 3. Follow-Up System

### Goal
Staff can log outcome of follow-up contacts and schedule next follow-up steps. Reminders sent via FCM push.

### Database
- **Extend `member_follow_up_actions`:**
  - `action_type` TEXT — replaces hardcoded `contacted`
    - Allowed values: `contacted`, `not_reachable`, `returned`, `transferred_out`, `needs_visit`
  - `scheduled_follow_up_at` TIMESTAMPTZ NULLABLE — next follow-up date/time
  - `outcome_note` TEXT NULLABLE — staff notes
  - Index on `scheduled_follow_up_at` for reminder queries

### Follow-Up Reminder Push
- Edge Function cron job runs daily at **8 AM**
- Queries `member_follow_up_actions` where `DATE(scheduled_follow_up_at) = today` AND `action_type NOT IN ('returned', 'transferred_out')`
- Sends FCM push to all staff devices: "Follow-up due: [Member Name]"

### Flutter UI
- Follow-up action sheet gains:
  - Dropdown: action type (contacted / not reachable / returned / transferred out / needs visit)
  - Date picker: "Schedule next follow-up" (optional)
  - Text field: outcome note (optional)
- Absent members list shows overdue/due-today follow-up indicator icon

---

## 4. Birthday & Anniversary System

### Goal
Staff receive push notifications the evening before and morning of each member's birthday and anniversary. No client-side detection.

### Database
- **New table: `birthday_notification_log`**
  - `id` UUID PK
  - `member_id` UUID → members
  - `notification_type` TEXT: `birthday_eve`, `birthday_morning`, `anniversary_eve`, `anniversary_morning`
  - `sent_at` TIMESTAMPTZ DEFAULT now()
  - `year` INT — calendar year of notification
  - Unique constraint on `(member_id, notification_type, year)` — prevents re-sending

### Edge Function Cron Jobs
- **9 PM nightly job (`notify_birthdays_eve`):**
  - Queries members where `birthday_md = tomorrow's MM-DD`
  - Checks log — skips if already sent this year
  - Sends FCM to all staff: "Tomorrow is [Name]'s birthday"
  - Logs to `birthday_notification_log`
  - Repeats for `anniversary_md`
- **8 AM morning job (`notify_birthdays_morning`):**
  - Queries members where `birthday_md = today's MM-DD`
  - Same check/send/log flow
  - Message: "Today is [Name]'s birthday — remember to reach out"
  - Repeats for `anniversary_md`

### Flutter
- Remove client-side birthday detection from `home_screen.dart`
- Remove `showBirthdayNotification()` and `showAnniversaryNotification()` local calls
- Server handles all birthday notifications

---

## 5. Notifications System (Unified)

### Goal
Single FCM-based push infrastructure serving all server-triggered notifications. Device tokens managed per-staff-member. Deep linking to relevant screens on tap.

### FCM Setup
- Firebase project created
- `google-services.json` → Flutter Android
- `GoogleService-Info.plist` → Flutter iOS
- `firebase_messaging` Flutter package added

### Database
- **New table: `device_tokens`**
  - `id` UUID PK
  - `staff_id` UUID → staff/users
  - `token` TEXT UNIQUE
  - `platform` TEXT (`android` / `ios`)
  - `updated_at` TIMESTAMPTZ DEFAULT now()

### Token Management (Flutter)
- On app launch: request FCM permission → get token → upsert into `device_tokens` with `staff_id`
- On logout: delete token from `device_tokens`
- `FirebaseMessaging.onTokenRefresh` stream → upserts new token automatically

### Push Helper (Edge Function)
- Shared helper `send_push_notification(tokens[], title, body, data)` — wraps FCM HTTP v1 API
- All other Edge Functions call this helper
- Stale/invalid tokens (FCM returns `UNREGISTERED`) auto-deleted from `device_tokens`

### Notification Deep Links
| Notification | Deep Link Destination |
|---|---|
| Birthday / Anniversary | Member profile screen |
| Follow-up reminder | Follow-up list filtered to that member |
| Absence alert | Absent members list |
| Session generation | Sessions screen |

### Notification Handling (Flutter)
- Foreground: in-app banner
- Background: system tray
- Terminated: app opens to deep-linked screen on tap

### What Changes
- `flutter_local_notifications` removed for birthday and absence notifications (FCM replaces)
- `flutter_local_notifications` kept only for weekly session generation notification (locally triggered)
- Notification ID collision risk eliminated (server-sent notifications have no hashCode IDs)

---

## Edge Functions Summary

| Function | Trigger | Purpose |
|---|---|---|
| `award_points` (DB trigger) | INSERT on `clock_ins` where `status = 'present'` | Insert into `points_ledger` |
| `evaluate_achievements` | Nightly cron + post-clock-in | Unlock new achievements |
| `notify_birthdays_eve` | Cron 9 PM nightly | Birthday/anniversary eve push |
| `notify_birthdays_morning` | Cron 8 AM daily | Birthday/anniversary morning push |
| `follow_up_reminders` | Cron 8 AM daily | Due follow-up push |
| `send_push_notification` | Called by other functions | FCM HTTP v1 wrapper |

---

## Migration Order
1. `points_ledger` table + trigger
2. `member_achievements` table
3. `birthday_notification_log` table
4. `device_tokens` table
5. Extend `member_follow_up_actions` columns
6. Update leaderboard views
7. Deploy Edge Functions
8. Flutter: FCM setup + token management
9. Flutter: UI updates (achievements, follow-up sheet, deep links)
10. Flutter: Remove client-side birthday detection
