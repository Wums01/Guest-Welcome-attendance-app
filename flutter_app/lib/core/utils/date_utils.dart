// lib/core/utils/date_utils.dart
//
// Utility functions for date/time handling.
// Mirrors the inline utilities spread across Next.js page components.

/// Returns the current time in Lagos timezone (Africa/Lagos = UTC+1, no DST).
/// Returns a naive (non-UTC) DateTime so comparisons with _parseTimeOnDay
/// (which also returns naive local DateTimes) are consistent regardless of
/// the device's local timezone setting.
DateTime nowInLagos() {
  final utc = DateTime.now().toUtc();
  final adjusted = utc.add(const Duration(hours: 1));
  // Strip the UTC flag — both nowInLagos() and _parseTimeOnDay() must be
  // naive so that isBefore/isAfter comparisons work correctly.
  return DateTime(adjusted.year, adjusted.month, adjusted.day,
      adjusted.hour, adjusted.minute, adjusted.second,
      adjusted.millisecond, adjusted.microsecond);
}

/// Formats a DateTime as "YYYY-MM-DD".
String formatDateISO(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}'
      '-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

/// Formats a DateTime as "MM-DD" (birthday/anniversary format).
String formatMMDD(DateTime d) {
  return '${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

/// Formats a DateTime as "HH:mm".
String formatTime(DateTime d) {
  return '${d.hour.toString().padLeft(2, '0')}'
      ':${d.minute.toString().padLeft(2, '0')}';
}

/// Returns an appropriate greeting based on the current hour.
String greetingFromHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// Returns true if [target] (as MM-DD) falls within [days] days from today
/// (exclusive of today itself). Used for "upcoming celebrations" logic.
bool isWithinDays(String mmdd, int days) {
  final today = nowInLagos();
  final todayMMDD = formatMMDD(today);
  if (mmdd == todayMMDD) return false;

  final targetThisYear =
      DateTime(today.year, int.parse(mmdd.split('-')[0]),
          int.parse(mmdd.split('-')[1]));

  // If this year's date has already passed, check next year
  final target = targetThisYear.isBefore(today)
      ? DateTime(today.year + 1, targetThisYear.month, targetThisYear.day)
      : targetThisYear;

  final startOfToday =
      DateTime(today.year, today.month, today.day);
  final cutoff = startOfToday.add(Duration(days: days));

  return target.isAfter(startOfToday) && !target.isAfter(cutoff);
}

/// Parses a "YYYY-MM-DD" date string into a DateTime at midnight.
DateTime parseDateISO(String date) {
  final parts = date.split('-');
  return DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// Builds a DateTime from a date string ("YYYY-MM-DD") and a time string ("HH:mm").
DateTime dateTimeFromDateAndTime(String date, String time) {
  final d = parseDateISO(date);
  final parts = time.split(':');
  return DateTime(d.year, d.month, d.day, int.parse(parts[0]),
      int.parse(parts[1]));
}

/// Returns a human-readable countdown string.
/// Mirrors msToCountdown() in check-in/page.tsx.
String msToCountdown(int ms) {
  if (ms <= 0) return 'Open now';
  final totalMins = (ms / 60000).ceil();
  if (totalMins < 60) return 'Opens in $totalMins min${totalMins == 1 ? '' : 's'}';
  final hrs = totalMins ~/ 60;
  final mins = totalMins % 60;
  return 'Opens in ${hrs}h ${mins}m';
}

/// Returns true when [now] is within the session's clock-in window.
/// - If both [startTime] and [endTime] are null → always open (e.g. Wednesday service).
/// - If only [startTime] is set → open once start is reached, no closing.
/// - If both are set → open between startTime and endTime.
bool isWithinSessionWindow(String? startTime, String? endTime, DateTime now) {
  if (startTime == null) return true; // no gate
  final start = _parseTimeOnDay(startTime, now);
  if (now.isBefore(start)) return false; // too early
  if (endTime == null) return true; // open-ended
  final end = _parseTimeOnDay(endTime, now);
  return now.isBefore(end);
}

/// Returns an enum describing the current gate state for a session.
enum SessionGateState { open, tooEarly, closed, noGate }

SessionGateState sessionGateState(String? startTime, String? endTime, DateTime now) {
  if (startTime == null) return SessionGateState.noGate;
  final start = _parseTimeOnDay(startTime, now);
  if (now.isBefore(start)) return SessionGateState.tooEarly;
  if (endTime == null) return SessionGateState.open;
  final end = _parseTimeOnDay(endTime, now);
  return now.isBefore(end) ? SessionGateState.open : SessionGateState.closed;
}

/// Returns milliseconds until [timeStr] (HH:mm) on [forDay].
int msUntilTime(String timeStr, DateTime forDay) {
  final target = _parseTimeOnDay(timeStr, forDay);
  final diff = target.difference(forDay).inMilliseconds;
  return diff < 0 ? 0 : diff;
}

DateTime _parseTimeOnDay(String timeStr, DateTime day) {
  final parts = timeStr.split(':');
  return DateTime(day.year, day.month, day.day,
      int.parse(parts[0]), int.parse(parts[1]));
}

/// Returns the Sunday that starts the week containing [d].
/// Flutter weekday: 1=Mon … 6=Sat, 7=Sun.  Sunday offset = 0, Mon=1 … Sat=6.
DateTime startOfWeek(DateTime d) {
  final offset = d.weekday == 7 ? 0 : d.weekday;
  return DateTime(d.year, d.month, d.day - offset);
}
