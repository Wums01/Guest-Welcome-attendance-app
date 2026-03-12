# Guest Welcome Attendance App — Master Todo

_Last updated: 2026-03-12_

---

## 🔴 CRITICAL — Core Attendance Flow

- [x] Fix "LIVE NOW" badge: now uses sessionGateState (checks endTime)
- [ ] **Fix check-in entry point**: Home "Start Check-in" button (and session cards) must go to `/sessions/:id/checkin`, not `/sessions/:id`. Session Detail screen must also have a "Start Check-in" button.
- [ ] **Verify attendance works end-to-end**: QR scan → clock in → appears as Present in session detail
- [ ] **Manual code input check-in** (`/sessions/:id/code`) — screen exists but is it reachable from the normal UI? Add entry point.

---

## 🟠 HIGH — Registration & Member Identity

- [x] **QR code on registration success**: `QrImageView` displayed on success screen
- [x] **Copy offline code button**: Tap to copy 6-digit code to clipboard on success screen
- [x] **Share via WhatsApp**: Pre-filled message with name + code, opens `wa.me` deeplink
- [x] **Member detail screen** (`/members/:id`): Full profile, attendance history, QR code, edit form
- [x] **Edit member**: `MemberService.updateMember()` added; edit form on member detail

---

## 🟠 HIGH — Programs / Sessions Organization

- [x] **Sessions grouped inside Programs**: `ProgramDetailScreen` at `/programs/:id` — program info card, sessions list, tappable session rows → `/sessions/:id`
  - Programs screen: `_ProgramCard` tappable → navigate to detail
  - Sunday programs: "Create Sunday Sessions" button → date picker → `createSundaySessions`
  - Wednesday programs: "Create Wednesday Session" button → date picker → `createWednesdaySessions`
- [x] **Session detail → Start Check-in button**: QR scan icon in AppBar navigates to `/sessions/:id/checkin`
- [x] **Wednesday session creation UI**: Exposed in `ProgramDetailScreen` for Wednesday-type programs

---

## 🟡 MEDIUM — Icons & Dead Buttons

All static icons and empty `onPressed: () {}` buttons:

| Screen | Element | Fix |
|---|---|---|
| Home | `Icons.notifications_outlined` (no tap) | Wrap in `IconButton` → navigate to notifications screen (or show a sheet for now) |
| Home | "See All" TextButton (birthdays) | Navigate to a full celebrations list (or filter members by upcoming BD/anniversary) |
| Home | "Call" button (follow-up) | ✅ Wired to `url_launcher` → `tel:` URL |
| Members | `Icons.notifications_outlined` (no tap) | Same as Home bell |
| Members | `Icons.menu` / burger (no tap) | Open end drawer OR navigate to next tab |
| Members | `Icons.tune` filter icon (no tap) | Open filter sheet (by team, role, etc.) |
| Sessions | `Icons.menu` (no tap) | Consistent with Members |
| Sessions | `Icons.account_circle_outlined` (no tap) | Navigate to profile / settings |
| Session Detail | `Icons.more_vert` (empty onPressed) | Options: Export, Share session link, etc. |
| Session Detail | `Icons.sort` (no tap) | Sort attendance list (A-Z, by team, by status) |
| Programs | `Icons.more_vert` AppBar (empty onPressed) | Filter/sort programs |
| Reports | `Icons.filter_list_outlined` (empty onPressed) | Date range / type filter |
| Reports | "SEE ALL" TextButton (empty onPressed) | Full leaderboard screen or expanded list |

---

## 🟡 MEDIUM — Point System

- [ ] Confirm: 1 clock-in (present) per session = 1 point. Monthly & yearly aggregation.
- [ ] Points already tracked in `present_count` column and shown in Reports as "pts". Verify DB trigger is correct.
- [x] Show member's own points on Home screen (Top 3 leaderboard with "See All" → Reports)
- [ ] Show member's points on Member Detail screen (future).

---

## 🟡 MEDIUM — Session Lifecycle

- [ ] After Sunday end time → session is "Ended" (LIVE NOW already fixed). Mark sessions as finalized when all absences are recorded.
- [ ] Sessions that are finalized should show a lock icon / "Finalized" badge in the sessions list.
- [ ] Consider: auto-finalize sessions at midnight after their date.

---

## 🟢 LOWER — Notifications

- [ ] **Bell icon**: Currently no notification center screen exists. Create a basic `NotificationsScreen` listing recent alerts (birthdays, absences, anniversaries).
- [ ] **Local notifications**: `NotificationService` already exists in `lib/core/notifications.dart`. Wire up birthday and absence triggers properly.
- [ ] **Notification badge dot**: Blue dot on Members bell exists; need to wire up count from unread notifications.

---

## 🟢 LOWER — Reports (do last, after data collection works)

- [ ] Attendance Trends chart: replace "Chart coming soon" with a real chart (`fl_chart` or `syncfusion_flutter_charts`).
- [ ] Reports filter: date range picker, filter by type (Sunday/Wednesday), filter by team.
- [ ] Full leaderboard screen (when "SEE ALL" is tapped).
- [ ] Export attendance data (CSV/PDF).
- [ ] Monthly vs yearly toggle in leaderboard.

---

## 🔵 FUTURE / LATER

- [ ] **Assistant permissions**: Assistants should not see other team members' data. Auth guard by team.
- [ ] **Program edit form**: Edit title, dates, virtual flag on existing programs.
- [ ] **Wednesday session UI**: Expose `createWednesdaySessions()` in Settings or Programs screen.
- [ ] **Member card photo / avatar upload**: Currently initials only.
- [ ] **Offline mode**: Cache member list locally for check-in without network.

---

## ✅ DONE

- [x] Fix LIVE NOW end-time bug (sessions_screen.dart)
- [x] Fix "Add Team Lead" bootstrap lockout (profile_picker_screen.dart)
- [x] Rename "staff" → "team lead" across all UI text
- [x] Profile overflow fix (childAspectRatio 0.78 → 0.70)
- [x] Add Sign Out button to assistant picker sheet
- [x] Staff authentication (bcrypt via pgcrypto RPCs)
- [x] Profile picker with team lead tiles + assistant group tile
- [x] Offline code check-in screen (6-digit keypad)
- [x] QR scan check-in screen (with gate logic)
- [x] Session gate state (tooEarly / open / closed / noGate)
- [x] Birthday & anniversary celebration cards on Home
- [x] Absence follow-up section on Home
- [x] Leaderboard with points in Reports
