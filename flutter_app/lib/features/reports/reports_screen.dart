// lib/features/reports/reports_screen.dart
//
// Reports: 4-tab layout — Daily | Weekly | Monthly | Yearly
// Each tab has its own chart, summary stats, data list, and CSV export.

import 'dart:io';
import 'dart:math' show max;

import 'package:excel/excel.dart' as xls;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/attendance_export_entry.dart';
import '../../models/attendance_summary.dart';
import '../../models/enums.dart';
import '../../models/leaderboard_entry.dart';
import '../../services/report_service.dart';
import '../../core/utils/date_utils.dart';
import '../../app_theme/app_theme.dart';
import '../../widgets/team_badge.dart';
import '../../widgets/avatar_widget.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _ym(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _monthLabel(String yearMonth) {
  final parts = yearMonth.split('-');
  return DateFormat('MMM').format(
      DateTime(int.parse(parts[0]), int.parse(parts[1])));
}

List<String> _last6YMs(String pivotYM) {
  final parts = pivotYM.split('-');
  final pivot = DateTime(int.parse(parts[0]), int.parse(parts[1]));
  return List.generate(6, (i) {
    final d = DateTime(pivot.year, pivot.month - (5 - i), 1);
    return _ym(d);
  });
}

const _kDayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

// Daily — keyed by "YYYY-MM-DD"
final _dailyReportProvider =
    FutureProvider.autoDispose.family<List<AttendanceSummary>, String>(
  (ref, date) => ref.read(reportServiceProvider).getDailyReport(date),
);

// Weekly — keyed by Sunday start date "YYYY-MM-DD"
final _weeklyReportProvider =
    FutureProvider.autoDispose.family<List<AttendanceSummary>, String>(
  (ref, startDate) {
    final start = parseDateISO(startDate);
    final end = start.add(const Duration(days: 6));
    return ref
        .read(reportServiceProvider)
        .getSessionsByDateRange(formatDateISO(start), formatDateISO(end));
  },
);

// Monthly leaderboard — keyed by "YYYY-MM"
final _monthlyLeaderboardProvider =
    FutureProvider.autoDispose.family<List<LeaderboardEntry>, String>(
  (ref, yearMonth) =>
      ref.read(reportServiceProvider).getMonthlyLeaderboard(yearMonth),
);

final _monthlyGuestTotalProvider =
    FutureProvider.autoDispose.family<int, String>(
  (ref, yearMonth) =>
      ref.read(reportServiceProvider).getMonthlyGuestTotal(yearMonth),
);

// 6-month trend chart — keyed by pivot year-month (rightmost bar)
final _chartDataProvider = FutureProvider.autoDispose
    .family<List<({String month, int total})>, String>(
  (ref, pivotYM) async {
    final yms = _last6YMs(pivotYM);
    final results = await Future.wait(
      yms.map((ym) =>
          ref.read(reportServiceProvider).getMonthlyLeaderboard(ym)),
    );
    return List.generate(yms.length, (i) {
      final total = results[i].fold(0, (s, e) => s + e.presentCount);
      return (month: _monthLabel(yms[i]), total: total);
    });
  },
);

// Yearly 12-month chart — always current year
final _yearlyChartProvider = FutureProvider.autoDispose<
    List<({String month, int total})>>((ref) async {
  final year = nowInLagos().year;
  final yms = List.generate(
      12, (i) => '$year-${(i + 1).toString().padLeft(2, '0')}');
  final results = await Future.wait(
    yms.map((ym) =>
        ref.read(reportServiceProvider).getMonthlyLeaderboard(ym)),
  );
  return List.generate(12, (i) {
    final total = results[i].fold(0, (s, e) => s + e.presentCount);
    return (month: DateFormat('MMM').format(DateTime(year, i + 1)), total: total);
  });
});

// Yearly leaderboard — always current year
final _yearlyLeaderboardProvider =
    FutureProvider.autoDispose<List<LeaderboardEntry>>((ref) {
  final year = '${nowInLagos().year}';
  return ref.read(reportServiceProvider).getYearlyLeaderboard(year);
});

// ---------------------------------------------------------------------------
// ReportsScreen
// ---------------------------------------------------------------------------

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Daily
  late DateTime _selectedDate;

  // Weekly
  late DateTime _selectedWeekStart;

  // Monthly
  late String _selectedYearMonth;
  String _teamFilter = 'all';
  bool _allTime = false;

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final now = nowInLagos();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedWeekStart = startOfWeek(_selectedDate);
    _selectedYearMonth = _ym(now);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Computed helpers ─────────────────────────────────────────────────────

  String get _dateStr => formatDateISO(_selectedDate);
  String get _weekStr => formatDateISO(_selectedWeekStart);
  DateTime get _weekEnd => _selectedWeekStart.add(const Duration(days: 6));
  String get _year => '${nowInLagos().year}';

  List<LeaderboardEntry> _teamFiltered(List<LeaderboardEntry> entries) {
    if (_teamFilter == 'all') return entries;
    final team = Team.values.firstWhere(
      (t) => t.value == _teamFilter,
      orElse: () => Team.none,
    );
    return entries.where((e) => e.team == team).toList();
  }

  // ── Refresh ──────────────────────────────────────────────────────────────

  void _refreshActiveTab() {
    switch (_tabController.index) {
      case 0:
        ref.invalidate(_dailyReportProvider(_dateStr));
      case 1:
        ref.invalidate(_weeklyReportProvider(_weekStr));
      case 2:
        ref.invalidate(_monthlyLeaderboardProvider(_selectedYearMonth));
        ref.invalidate(_monthlyGuestTotalProvider(_selectedYearMonth));
        ref.invalidate(_chartDataProvider(_selectedYearMonth));
      case 3:
        ref.invalidate(_yearlyChartProvider);
        ref.invalidate(_yearlyLeaderboardProvider);
    }
  }

  // ── Export ───────────────────────────────────────────────────────────────

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      switch (_tabController.index) {
        case 0:
          await _exportDaily();
        case 1:
          await _exportWeekly();
        case 2:
          await _exportMonthly();
        case 3:
          await _exportYearly();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportDaily() async {
    final summaries = await ref.read(_dailyReportProvider(_dateStr).future);
    final rows = await ref.read(reportServiceProvider).getAttendanceExportRows(_dateStr);
    final bytes = _buildAttendanceWorkbook(
      title: 'Daily Attendance Sheet',
      subtitle: _dateStr,
      summaries: summaries,
      rows: rows,
    );
    await _shareBinaryFile(
      bytes,
      'daily_attendance_$_dateStr.xlsx',
      'Daily Attendance $_dateStr',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _exportWeekly() async {
    final summaries = await ref.read(_weeklyReportProvider(_weekStr).future);
    final rows = await ref
        .read(reportServiceProvider)
        .getAttendanceExportRowsByDateRange(_weekStr, formatDateISO(_weekEnd));
    final label =
        '${formatDateISO(_selectedWeekStart)}_to_${formatDateISO(_weekEnd)}';
    final bytes = _buildAttendanceWorkbook(
      title: 'Weekly Attendance Sheet',
      subtitle: label,
      summaries: summaries,
      rows: rows,
    );
    await _shareBinaryFile(
      bytes,
      'weekly_attendance_$label.xlsx',
      'Weekly Attendance $label',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _exportMonthly() async {
    final startDate = '$_selectedYearMonth-01';
    final parts = _selectedYearMonth.split('-');
    final monthStart = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
    final endDate = formatDateISO(monthEnd);

    final summaries = await ref
        .read(reportServiceProvider)
        .getSessionsByDateRange(startDate, endDate);
    final rows = await ref
        .read(reportServiceProvider)
        .getAttendanceExportRowsByDateRange(startDate, endDate);
    final bytes = _buildAttendanceWorkbook(
      title: 'Monthly Attendance Sheet',
      subtitle: _selectedYearMonth,
      summaries: summaries,
      rows: rows,
    );
    await _shareBinaryFile(
      bytes,
      'monthly_attendance_$_selectedYearMonth.xlsx',
      'Monthly Attendance $_selectedYearMonth',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _exportYearly() async {
    final startDate = '$_year-01-01';
    final endDate = '$_year-12-31';
    final summaries = await ref
        .read(reportServiceProvider)
        .getSessionsByDateRange(startDate, endDate);
    final rows = await ref
        .read(reportServiceProvider)
        .getAttendanceExportRowsByDateRange(startDate, endDate);
    final bytes = _buildAttendanceWorkbook(
      title: 'Yearly Attendance Sheet',
      subtitle: _year,
      summaries: summaries,
      rows: rows,
    );
    await _shareBinaryFile(
      bytes,
      'yearly_attendance_$_year.xlsx',
      'Yearly Attendance $_year',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _shareBinaryFile(
      List<int> bytes, String filename, String subject, String mimeType) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: subject,
    );
  }

  List<int> _buildAttendanceWorkbook({
    required String title,
    required String subtitle,
    required List<AttendanceSummary> summaries,
    required List<AttendanceExportEntry> rows,
  }) {
    final workbook = xls.Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Summary') {
      workbook.delete(defaultSheet);
    }

    final groupedRows = <String, List<AttendanceExportEntry>>{};
    for (final row in rows) {
      groupedRows.putIfAbsent(row.sessionId, () => []).add(row);
    }

    final summarySheet = workbook['Summary'];
    _writeSummarySheet(summarySheet, title, subtitle, summaries);

    for (final summary in summaries) {
      final safeName = _safeSheetName(
        '${summary.sessionDate}_${summary.sessionName}',
      );
      final sheet = workbook[safeName];
      _writeSessionSheet(
        sheet: sheet,
        summary: summary,
        rows: groupedRows[summary.sessionId] ?? const [],
      );
    }

    return workbook.save(fileName: 'attendance_export.xlsx') ?? <int>[];
  }

  void _writeSummarySheet(
    xls.Sheet sheet,
    String title,
    String subtitle,
    List<AttendanceSummary> summaries,
  ) {
    final totalPresent = summaries.fold<int>(0, (sum, item) => sum + item.presentCount);
    final totalAbsent = summaries.fold<int>(0, (sum, item) => sum + item.absentCount);
    final totalExcused = summaries.fold<int>(0, (sum, item) => sum + item.excusedCount);
    final totalGuests = summaries.fold<int>(0, (sum, item) => sum + item.newGuestCount);
    final totalMarked = summaries.fold<int>(0, (sum, item) => sum + item.totalMarked);

    sheet.merge(
      xls.CellIndex.indexByString('A1'),
      xls.CellIndex.indexByString('G1'),
    );
    _setCell(sheet, 'A1', title, style: _titleStyle());
    _setCell(sheet, 'A2', 'Period');
    _setCell(sheet, 'B2', subtitle, style: _pillStyle());
    _setCell(sheet, 'A4', 'Present', style: _tableHeaderStyle());
    _setCell(sheet, 'B4', totalPresent.toString(), style: _statStyle());
    _setCell(sheet, 'C4', 'Absent', style: _tableHeaderStyle());
    _setCell(sheet, 'D4', totalAbsent.toString(), style: _statStyle());
    _setCell(sheet, 'E4', 'Excused', style: _tableHeaderStyle());
    _setCell(sheet, 'F4', totalExcused.toString(), style: _statStyle());
    _setCell(sheet, 'A5', 'Guests', style: _tableHeaderStyle());
    _setCell(sheet, 'B5', totalGuests.toString(), style: _statStyle());
    _setCell(sheet, 'C5', 'Total Marked', style: _tableHeaderStyle());
    _setCell(sheet, 'D5', totalMarked.toString(), style: _statStyle());

    const headerRow = 7;
    final headers = [
      'Session',
      'Program',
      'Present',
      'Absent',
      'Excused',
      'Total',
      'Guests',
    ];
    for (int i = 0; i < headers.length; i++) {
      _setCellByIndex(sheet, i, headerRow, headers[i], style: _tableHeaderStyle());
    }

    for (int i = 0; i < summaries.length; i++) {
      final row = headerRow + 1 + i;
      final summary = summaries[i];
      _setCellByIndex(sheet, 0, row, summary.sessionName);
      _setCellByIndex(sheet, 1, row, summary.programTitle);
      _setCellByIndex(sheet, 2, row, summary.presentCount.toString());
      _setCellByIndex(sheet, 3, row, summary.absentCount.toString());
      _setCellByIndex(sheet, 4, row, summary.excusedCount.toString());
      _setCellByIndex(sheet, 5, row, summary.totalMarked.toString());
      _setCellByIndex(sheet, 6, row, summary.newGuestCount.toString());
    }
  }

  void _writeSessionSheet({
    required xls.Sheet sheet,
    required AttendanceSummary summary,
    required List<AttendanceExportEntry> rows,
  }) {
    sheet.merge(
      xls.CellIndex.indexByString('A1'),
      xls.CellIndex.indexByString('D1'),
    );
    _setCell(sheet, 'A1', summary.sessionName, style: _titleStyle());
    _setCell(sheet, 'A2', 'Date');
    _setCell(sheet, 'B2', summary.sessionDate, style: _pillStyle());
    _setCell(sheet, 'C2', 'Program');
    _setCell(sheet, 'D2', summary.programTitle, style: _pillStyle());

    _setCell(sheet, 'A4', 'Present', style: _tableHeaderStyle());
    _setCell(sheet, 'B4', summary.presentCount.toString(), style: _statStyle());
    _setCell(sheet, 'C4', 'Absent', style: _tableHeaderStyle());
    _setCell(sheet, 'D4', summary.absentCount.toString(), style: _statStyle());
    _setCell(sheet, 'A5', 'Excused', style: _tableHeaderStyle());
    _setCell(sheet, 'B5', summary.excusedCount.toString(), style: _statStyle());
    _setCell(sheet, 'C5', 'Total', style: _tableHeaderStyle());
    _setCell(sheet, 'D5', summary.totalMarked.toString(), style: _statStyle());

    final headers = ['Member name', 'Clocked in', 'Service', 'Status'];
    for (int i = 0; i < headers.length; i++) {
      _setCellByIndex(sheet, i, 7, headers[i], style: _tableHeaderStyle());
    }

    final sortedRows = [...rows]
      ..sort((a, b) {
        final byStatus = a.status.value.compareTo(b.status.value);
        if (byStatus != 0) return byStatus;
        return a.memberName.compareTo(b.memberName);
      });

    for (int i = 0; i < sortedRows.length; i++) {
      final rowIndex = 8 + i;
      final row = sortedRows[i];
      _setCellByIndex(sheet, 0, rowIndex, row.memberName);
      _setCellByIndex(sheet, 1, rowIndex, DateFormat('hh:mm a').format(row.clockedAt));
      _setCellByIndex(sheet, 2, rowIndex, row.sessionName);
      _setCellByIndex(sheet, 3, rowIndex, _capitalize(row.status.value));
    }
  }

  void _setCell(
    xls.Sheet sheet,
    String cell,
    String value, {
    xls.CellStyle? style,
  }) {
    final index = xls.CellIndex.indexByString(cell);
    sheet.cell(index).value = xls.TextCellValue(value);
    if (style != null) {
      sheet.cell(index).cellStyle = style;
    }
  }

  void _setCellByIndex(
    xls.Sheet sheet,
    int column,
    int row,
    String value, {
    xls.CellStyle? style,
  }) {
    final index = xls.CellIndex.indexByColumnRow(
      columnIndex: column,
      rowIndex: row,
    );
    sheet.cell(index).value = xls.TextCellValue(value);
    if (style != null) {
      sheet.cell(index).cellStyle = style;
    }
  }

  String _safeSheetName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\\/*?:\[\]]'), '').trim();
    if (cleaned.isEmpty) return 'Session';
    return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  xls.CellStyle _titleStyle() => xls.CellStyle(
        bold: true,
        fontSize: 15,
        fontColorHex: xls.ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: xls.ExcelColor.fromHexString('#0F49BD'),
        horizontalAlign: xls.HorizontalAlign.Center,
      );

  xls.CellStyle _pillStyle() => xls.CellStyle(
        bold: true,
        fontColorHex: xls.ExcelColor.fromHexString('#0F49BD'),
        backgroundColorHex: xls.ExcelColor.fromHexString('#EFF6FF'),
      );

  xls.CellStyle _tableHeaderStyle() => xls.CellStyle(
        bold: true,
        fontColorHex: xls.ExcelColor.fromHexString('#0F172A'),
        backgroundColorHex: xls.ExcelColor.fromHexString('#DBEAFE'),
      );

  xls.CellStyle _statStyle() => xls.CellStyle(
        bold: true,
        fontColorHex: xls.ExcelColor.fromHexString('#0F49BD'),
        backgroundColorHex: xls.ExcelColor.fromHexString('#F8FAFC'),
      );

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        centerTitle: false,
        title: const Text('Reports'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export report',
              onPressed: _exportCsv,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.slate500,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
            Tab(text: 'Yearly'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () async => _refreshActiveTab(),
              child: _buildDailyTab(),
            ),
            RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () async => _refreshActiveTab(),
              child: _buildWeeklyTab(),
            ),
            RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () async => _refreshActiveTab(),
              child: _buildMonthlyTab(),
            ),
            RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () async => _refreshActiveTab(),
              child: _buildYearlyTab(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Daily Tab ─────────────────────────────────────────────────────────────

  Widget _buildDailyTab() {
    final now = nowInLagos();
    final today = DateTime(now.year, now.month, now.day);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _PeriodNavBar(
          label: DateFormat('EEE, MMM d, y').format(_selectedDate),
          onPrev: () => setState(() =>
              _selectedDate = _selectedDate.subtract(const Duration(days: 1))),
          onNext: () => setState(
              () => _selectedDate = _selectedDate.add(const Duration(days: 1))),
          onReset: _selectedDate == today
              ? null
              : () => setState(() => _selectedDate = today),
          resetLabel: 'Today',
        ),
        Consumer(builder: (ctx, ref, _) {
          final dataAsync = ref.watch(_dailyReportProvider(_dateStr));
          return dataAsync.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(error: '$e'),
            data: (sessions) {
              if (sessions.isEmpty) {
                return const _EmptyState(message: 'No sessions on this date.');
              }
              final totalP = sessions.fold(0, (s, e) => s + e.presentCount);
              final totalA = sessions.fold(0, (s, e) => s + e.absentCount);
              final totalE = sessions.fold(0, (s, e) => s + e.excusedCount);
              final totalNewGuests =
                  sessions.fold(0, (s, e) => s + e.newGuestCount);
              final totalM = sessions.fold(0, (s, e) => s + e.totalMarked);
              final rateStr = totalM == 0
                  ? '0%'
                  : '${(totalP / totalM * 100).round()}%';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(children: [
                      Expanded(
                          child: _SummaryCard(
                              label: 'PRESENT',
                              value: '$totalP',
                              unit: 'members',
                              color: AppTheme.primary,
                              bg: AppTheme.primaryBg)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SummaryCard(
                              label: 'ABSENT',
                              value: '$totalA',
                              unit: 'members',
                              color: AppTheme.error,
                              bg: AppTheme.errorBg)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SummaryCard(
                              label: 'NEW GUESTS',
                              value: '$totalNewGuests',
                              unit: 'people',
                              color: AppTheme.primary,
                              bg: AppTheme.primaryBg)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SummaryCard(
                              label: 'EXCUSED',
                              value: '$totalE',
                              unit: 'members',
                              color: AppTheme.amber,
                              bg: AppTheme.amberBg)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      '${sessions.length} service${sessions.length == 1 ? '' : 's'} · $rateStr attendance rate',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.slate500),
                    ),
                  ),
                  // Chart
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _SectionHeader(title: 'Attendance by Service'),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _GroupedDailyBarChart(sessions: sessions),
                  ),
                  const SizedBox(height: 6),
                  const _ChartLegend(items: [
                    (label: 'Present', color: AppTheme.primary),
                    (label: 'Absent', color: AppTheme.error),
                    (label: 'Excused', color: AppTheme.amber),
                  ]),
                  // Session detail cards
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _SectionHeader(title: 'Session Details'),
                  ),
                  const SizedBox(height: 8),
                  ...sessions.map((s) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: _SessionCard(summary: s, showDate: false),
                      )),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        }),
      ],
    );
  }

  // ── Weekly Tab ────────────────────────────────────────────────────────────

  Widget _buildWeeklyTab() {
    final now = nowInLagos();
    final thisWeekStart = startOfWeek(DateTime(now.year, now.month, now.day));
    final weekLabel =
        '${DateFormat('MMM d').format(_selectedWeekStart)} – '
        '${DateFormat('MMM d, y').format(_weekEnd)}';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _PeriodNavBar(
          label: weekLabel,
          onPrev: () => setState(() =>
              _selectedWeekStart =
                  _selectedWeekStart.subtract(const Duration(days: 7))),
          onNext: () => setState(() =>
              _selectedWeekStart =
                  _selectedWeekStart.add(const Duration(days: 7))),
          onReset: _selectedWeekStart == thisWeekStart
              ? null
              : () => setState(() => _selectedWeekStart = thisWeekStart),
          resetLabel: 'This Week',
        ),
        Consumer(builder: (ctx, ref, _) {
          final dataAsync = ref.watch(_weeklyReportProvider(_weekStr));
          return dataAsync.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(error: '$e'),
            data: (sessions) {
              if (sessions.isEmpty) {
                return const _EmptyState(message: 'No sessions this week.');
              }
              final totalP = sessions.fold(0, (s, e) => s + e.presentCount);
              final totalA = sessions.fold(0, (s, e) => s + e.absentCount);
              // Aggregate by day of week (0=Sun … 6=Sat)
              final dayTotals = List<int>.filled(7, 0);
              for (final s in sessions) {
                final date = parseDateISO(s.sessionDate);
                final dow = date.weekday == 7 ? 0 : date.weekday;
                dayTotals[dow] += s.presentCount;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(children: [
                      Expanded(
                          child: _SummaryCard(
                              label: 'SESSIONS',
                              value: '${sessions.length}',
                              unit: 'services',
                              color: AppTheme.primary,
                              bg: AppTheme.primaryBg)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SummaryCard(
                              label: 'PRESENT',
                              value: '$totalP',
                              unit: 'check-ins',
                              color: AppTheme.success,
                              bg: AppTheme.successBg)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SummaryCard(
                              label: 'ABSENT',
                              value: '$totalA',
                              unit: 'members',
                              color: AppTheme.error,
                              bg: AppTheme.errorBg)),
                    ]),
                  ),
                  // Chart
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _SectionHeader(title: 'Attendance by Day'),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _WeeklyDayChart(dayTotals: dayTotals),
                  ),
                  // Sessions list grouped by date
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _SectionHeader(title: 'Session Details'),
                  ),
                  const SizedBox(height: 8),
                  ...sessions.map((s) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: _SessionCard(summary: s, showDate: true),
                      )),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        }),
      ],
    );
  }

  // ── Monthly Tab ───────────────────────────────────────────────────────────

  Widget _buildMonthlyTab() {
    final now = nowInLagos();
    final parts = _selectedYearMonth.split('-');
    final ymDate =
        DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final leaderboardAsync = _allTime
        ? ref.watch(_yearlyLeaderboardProvider)
        : ref.watch(_monthlyLeaderboardProvider(_selectedYearMonth));
    final guestTotalAsync = ref.watch(_monthlyGuestTotalProvider(_selectedYearMonth));
    final chartAsync = ref.watch(_chartDataProvider(_selectedYearMonth));

    final bestScore = leaderboardAsync.maybeWhen(
      data: (all) {
        final filtered = _teamFiltered(all);
        return filtered.isNotEmpty ? filtered.first.presentCount : 0;
      },
      orElse: () => 0,
    );

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Month nav bar
        SliverToBoxAdapter(
          child: _PeriodNavBar(
            label: DateFormat('MMMM y').format(ymDate),
            onPrev: () => setState(() {
              final d = DateTime(ymDate.year, ymDate.month - 1);
              _selectedYearMonth = _ym(d);
            }),
            onNext: () {
              // Don't navigate past current year+2 months
              final limit = DateTime(now.year, now.month + 2);
              final next = DateTime(ymDate.year, ymDate.month + 1);
              if (!next.isAfter(limit)) {
                setState(() => _selectedYearMonth = _ym(next));
              }
            },
            onReset: _selectedYearMonth == _ym(now)
                ? null
                : () => setState(() => _selectedYearMonth = _ym(now)),
            resetLabel: 'This Month',
          ),
        ),

        // Team filter chips
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _TeamChip(
                  label: 'Overall',
                  selected: _teamFilter == 'all',
                  onTap: () => setState(() => _teamFilter = 'all')),
              const SizedBox(width: 8),
              _TeamChip(
                  label: 'Team A',
                  selected: _teamFilter == 'Team A',
                  onTap: () => setState(() => _teamFilter = 'Team A')),
              const SizedBox(width: 8),
              _TeamChip(
                  label: 'Team B',
                  selected: _teamFilter == 'Team B',
                  onTap: () => setState(() => _teamFilter = 'Team B')),
              const SizedBox(width: 8),
              _TeamChip(
                  label: 'Team C',
                  selected: _teamFilter == 'Team C',
                  onTap: () => setState(() => _teamFilter = 'Team C')),
            ]),
          ),
        ),

        // Stats cards
        SliverToBoxAdapter(
          child: leaderboardAsync.when(
            loading: () => const SizedBox(height: 80),
            error: (_, __) => const SizedBox.shrink(),
            data: (all) {
              final entries = _teamFiltered(all);
              final n = entries.length;
              final avg = n == 0
                  ? 0.0
                  : entries.map((e) => e.presentCount).fold(0, (a, b) => a + b) /
                      n;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                          child: _SummaryCard(
                              label: 'AVG POINTS',
                              value: avg.toStringAsFixed(1),
                              unit: 'pts',
                              color: AppTheme.primary,
                              bg: AppTheme.primaryBg)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _SummaryCard(
                              label: 'TOTAL MEMBERS',
                              value: '$n',
                              unit: 'members',
                              color: AppTheme.success,
                              bg: AppTheme.successBg)),
                    ]),
                    const SizedBox(height: 12),
                    guestTotalAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (guestTotal) => _SummaryCard(
                          label: 'GUESTS THIS MONTH',
                          value: '$guestTotal',
                          unit: 'guests',
                          color: AppTheme.amber,
                          bg: AppTheme.amberBg),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Trend chart
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(title: 'Attendance Trends'),
                const SizedBox(height: 4),
                const Text(
                  'Total check-ins per month (last 6 months)',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
                const SizedBox(height: 12),
                chartAsync.when(
                  loading: () => _chartPlaceholder(
                      child: const CircularProgressIndicator()),
                  error: (e, _) => _chartPlaceholder(
                      child: Text('Chart error: $e',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.slate500))),
                  data: (months) => _MonthlyTrendChart(months: months),
                ),
              ],
            ),
          ),
        ),

        // Leaderboard header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                      child: _SectionHeader(title: 'Leaderboard')),
                  GestureDetector(
                    onTap: () => setState(() => _allTime = !_allTime),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _allTime ? 'All Time' : 'This Month',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  '1 service = 1 point  \u00b7  Best: $bestScore pts',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
        ),

        // Leaderboard list
        leaderboardAsync.when(
          loading: () => const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()))),
          error: (e, _) =>
              SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
          data: (all) {
            final entries = _teamFiltered(all);
            if (entries.isEmpty) {
              return const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text('No leaderboard data yet.',
                              style:
                                  TextStyle(color: AppTheme.slate500)))));
            }
            final maxP = entries
                .map((e) => e.presentCount)
                .reduce((a, b) => a > b ? a : b);
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final e = entries[i];
                    final pct = maxP == 0
                        ? 0
                        : (e.presentCount / maxP * 100).round();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LeaderboardCard(
                          entry: e,
                          rank: i + 1,
                          isTop: i == 0,
                          attendancePct: pct),
                    );
                  },
                  childCount: entries.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Yearly Tab ────────────────────────────────────────────────────────────

  Widget _buildYearlyTab() {
    final chartAsync = ref.watch(_yearlyChartProvider);
    final leaderboardAsync = ref.watch(_yearlyLeaderboardProvider);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Year header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '$_year Year in Review',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A)),
            ),
          ),
        ),

        // Summary cards
        SliverToBoxAdapter(
          child: chartAsync.when(
            loading: () => const SizedBox(height: 80),
            error: (_, __) => const SizedBox.shrink(),
            data: (months) {
              final total = months.fold(0, (s, m) => s + m.total);
              final bestMonth = months.isEmpty
                  ? '—'
                  : months
                      .reduce((a, b) => b.total > a.total ? b : a)
                      .month;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Expanded(
                      child: _SummaryCard(
                          label: 'TOTAL CHECK-INS',
                          value: '$total',
                          unit: 'this year',
                          color: AppTheme.primary,
                          bg: AppTheme.primaryBg)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _SummaryCard(
                          label: 'BEST MONTH',
                          value: bestMonth,
                          unit: 'most check-ins',
                          color: AppTheme.amber,
                          bg: AppTheme.amberBg)),
                ]),
              );
            },
          ),
        ),

        // 12-month chart
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(title: '12-Month Trend'),
                const SizedBox(height: 4),
                Text(
                  'Total check-ins per month in $_year',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.slate500),
                ),
                const SizedBox(height: 12),
                chartAsync.when(
                  loading: () => _chartPlaceholder(
                      child: const CircularProgressIndicator()),
                  error: (e, _) => _chartPlaceholder(
                      child: Text('Chart error: $e',
                          style: const TextStyle(fontSize: 12))),
                  data: (months) => _YearlyBarChart(months: months),
                ),
              ],
            ),
          ),
        ),

        // Yearly leaderboard header
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(title: 'Yearly Leaderboard'),
                SizedBox(height: 4),
                Text(
                  '1 service = 1 point · ranked by total',
                  style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
        ),

        // Yearly leaderboard list
        leaderboardAsync.when(
          loading: () => const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()))),
          error: (e, _) =>
              SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
          data: (entries) {
            if (entries.isEmpty) {
              return const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text('No data for this year yet.',
                              style:
                                  TextStyle(color: AppTheme.slate500)))));
            }
            final maxP =
                entries.map((e) => e.presentCount).reduce((a, b) => a > b ? a : b);
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final e = entries[i];
                    final pct = maxP == 0
                        ? 0
                        : (e.presentCount / maxP * 100).round();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LeaderboardCard(
                          entry: e,
                          rank: i + 1,
                          isTop: i == 0,
                          attendancePct: pct),
                    );
                  },
                  childCount: entries.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _chartPlaceholder({required Widget child}) => Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Center(child: child),
      );
}

// ---------------------------------------------------------------------------
// _GroupedDailyBarChart — 3 rods per session (present/absent/excused)
// ---------------------------------------------------------------------------

class _GroupedDailyBarChart extends StatelessWidget {
  const _GroupedDailyBarChart({required this.sessions});
  final List<AttendanceSummary> sessions;

  @override
  Widget build(BuildContext context) {
    final maxY = sessions.isEmpty
        ? 10.0
        : sessions
            .map((s) => max(max(s.presentCount, s.absentCount),
                    s.excusedCount)
                .toDouble())
            .reduce((a, b) => a > b ? a : b);
    final ceiling = maxY == 0 ? 10.0 : (maxY * 1.3).ceilToDouble();

    final chartWidth = max(300.0, sessions.length * 90.0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: chartWidth,
        height: 220,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: BarChart(
            BarChartData(
              maxY: ceiling,
              minY: 0,
              groupsSpace: 16,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1E3A5F),
                  tooltipRoundedRadius: 8,
                  getTooltipItem: (group, gi, rod, ri) {
                    final labels = ['Present', 'Absent', 'Excused'];
                    return BarTooltipItem(
                      '${labels[ri]}: ${rod.toY.toInt()}',
                      const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= sessions.length) {
                        return const SizedBox.shrink();
                      }
                      final name = sessions[i].sessionName;
                      final words = name.split(' ');
                      final label = words.length >= 2
                          ? '${words[0]}\n${words[1]}'
                          : name.substring(0, name.length.clamp(0, 10));
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 9, color: AppTheme.slate500)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: ceiling == 0
                        ? 5
                        : (ceiling / 4).ceilToDouble(),
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.slate500),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppTheme.slate200.withValues(alpha: 0.6),
                  strokeWidth: 1,
                ),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(sessions.length, (i) {
                final s = sessions[i];
                return BarChartGroupData(
                  x: i,
                  barsSpace: 3,
                  barRods: [
                    BarChartRodData(
                      toY: s.presentCount.toDouble(),
                      color: AppTheme.primary,
                      width: 10,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: Radius.circular(3),
                      ),
                    ),
                    BarChartRodData(
                      toY: s.absentCount.toDouble(),
                      color: AppTheme.error,
                      width: 10,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: Radius.circular(3),
                      ),
                    ),
                    BarChartRodData(
                      toY: s.excusedCount.toDouble(),
                      color: AppTheme.amber,
                      width: 10,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: Radius.circular(3),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _WeeklyDayChart — 7 bars, one per day of week (Sun–Sat)
// ---------------------------------------------------------------------------

class _WeeklyDayChart extends StatelessWidget {
  const _WeeklyDayChart({required this.dayTotals});
  final List<int> dayTotals; // length 7, index 0=Sun

  @override
  Widget build(BuildContext context) {
    final maxY = dayTotals.isEmpty
        ? 10.0
        : dayTotals.map((v) => v.toDouble()).reduce((a, b) => a > b ? a : b);
    final ceiling = maxY == 0 ? 10.0 : (maxY * 1.3).ceilToDouble();

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: BarChart(
        BarChartData(
          maxY: ceiling,
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E3A5F),
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${rod.toY.toInt()} present',
                const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= _kDayLabels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_kDayLabels[i],
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.slate500)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval:
                    ceiling == 0 ? 5 : (ceiling / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.slate500),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.slate200.withValues(alpha: 0.6),
              strokeWidth: 1,
            ),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) {
            final hasData = dayTotals[i] > 0;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: dayTotals[i].toDouble(),
                  color: hasData
                      ? AppTheme.primary
                      : AppTheme.primary.withValues(alpha: 0.25),
                  width: 22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MonthlyTrendChart — 6 bars, existing design
// ---------------------------------------------------------------------------

class _MonthlyTrendChart extends StatelessWidget {
  const _MonthlyTrendChart({required this.months});
  final List<({String month, int total})> months;

  @override
  Widget build(BuildContext context) {
    final maxY = months.isEmpty
        ? 10.0
        : months
            .map((m) => m.total.toDouble())
            .reduce((a, b) => a > b ? a : b);
    final ceiling = maxY == 0 ? 10.0 : (maxY * 1.3).ceilToDouble();

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: BarChart(
        BarChartData(
          maxY: ceiling,
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E3A5F),
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${rod.toY.toInt()} pts',
                const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= months.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(months[i].month,
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.slate500)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval:
                    ceiling == 0 ? 5 : (ceiling / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.slate500),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.slate200.withValues(alpha: 0.6),
              strokeWidth: 1,
            ),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(months.length, (i) {
            final isCurrent = i == months.length - 1;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: months[i].total.toDouble(),
                  color: isCurrent
                      ? AppTheme.primary
                      : AppTheme.primary.withValues(alpha: 0.35),
                  width: 22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _YearlyBarChart — 12 bars (Jan–Dec)
// ---------------------------------------------------------------------------

class _YearlyBarChart extends StatelessWidget {
  const _YearlyBarChart({required this.months});
  final List<({String month, int total})> months;

  @override
  Widget build(BuildContext context) {
    final now = nowInLagos();
    final maxY = months.isEmpty
        ? 10.0
        : months
            .map((m) => m.total.toDouble())
            .reduce((a, b) => a > b ? a : b);
    final ceiling = maxY == 0 ? 10.0 : (maxY * 1.3).ceilToDouble();

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: BarChart(
        BarChartData(
          maxY: ceiling,
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E3A5F),
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${rod.toY.toInt()} pts',
                const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= months.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(months[i].month,
                        style: const TextStyle(
                            fontSize: 9, color: AppTheme.slate500)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval:
                    ceiling == 0 ? 5 : (ceiling / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.slate500),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.slate200.withValues(alpha: 0.6),
              strokeWidth: 1,
            ),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(months.length, (i) {
            // Highlight current month; past months full, future months dimmed
            final isCurrent = i + 1 == now.month;
            final isFuture = i + 1 > now.month;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: months[i].total.toDouble(),
                  color: isCurrent
                      ? AppTheme.amber
                      : isFuture
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : AppTheme.primary.withValues(alpha: 0.55),
                  width: 14,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(3),
                    topRight: Radius.circular(3),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ChartLegend
// ---------------------------------------------------------------------------

typedef _LegendItem = ({String label, Color color});

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.items});
  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: item.color,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 4),
                      Text(item.label,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate500,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PeriodNavBar
// ---------------------------------------------------------------------------

class _PeriodNavBar extends StatelessWidget {
  const _PeriodNavBar({
    required this.label,
    required this.onPrev,
    required this.onNext,
    this.onReset,
    this.resetLabel = 'Today',
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onReset;
  final String resetLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            color: AppTheme.primary,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF0F172A)),
            ),
          ),
          if (onReset != null) ...[
            GestureDetector(
              onTap: onReset,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  resetLabel,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 52),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            color: AppTheme.primary,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SessionCard
// ---------------------------------------------------------------------------

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.summary, required this.showDate});
  final AttendanceSummary summary;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final rate = summary.totalMarked == 0
        ? 0.0
        : summary.presentCount / summary.totalMarked * 100;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.sessionName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF0F172A)),
                    ),
                    Text(
                      summary.programTitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.slate500),
                    ),
                    if (showDate)
                      Text(
                        _formatDate(summary.sessionDate),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.slate500),
                      ),
                  ],
                ),
              ),
              // Attendance rate pill
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: rate >= 70
                      ? AppTheme.successBg
                      : rate >= 40
                          ? AppTheme.amberBg
                          : AppTheme.errorBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${rate.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: rate >= 70
                        ? AppTheme.success
                        : rate >= 40
                            ? AppTheme.amber
                            : AppTheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Stats row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MiniStat(
                  label: 'Present',
                  value: summary.presentCount,
                  color: AppTheme.primary,
                  bg: AppTheme.primaryBg),
              _MiniStat(
                  label: 'Absent',
                  value: summary.absentCount,
                  color: AppTheme.error,
                  bg: AppTheme.errorBg),
              _MiniStat(
                  label: 'New Guests',
                  value: summary.newGuestCount,
                  color: AppTheme.primary,
                  bg: AppTheme.primaryBg),
              _MiniStat(
                  label: 'Excused',
                  value: summary.excusedCount,
                  color: AppTheme.amber,
                  bg: AppTheme.amberBg),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Total: ${summary.totalMarked}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.slate500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final parts = iso.split('-');
    final d =
        DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    return DateFormat('EEE, MMM d, y').format(d);
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.label,
      required this.value,
      required this.color,
      required this.bg});
  final String label;
  final int value;
  final Color color, bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Poppins'),
          children: [
            TextSpan(
              text: '$value ',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: color),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bar_chart_outlined,
                  size: 48, color: AppTheme.slate200),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.slate500, fontSize: 14)),
            ],
          ),
        ),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('Error loading data: $error',
              style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ),
      );
}

class _TeamChip extends StatelessWidget {
  const _TeamChip(
      {required this.label,
      required this.selected,
      required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.slate200),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? Colors.white : AppTheme.slate500)),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A))),
        ],
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.bg,
  });
  final String label, value, unit;
  final Color color, bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate500,
                    letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(unit,
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.slate500)),
          ],
        ),
      );
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entry,
    required this.rank,
    required this.isTop,
    required this.attendancePct,
  });
  final LeaderboardEntry entry;
  final int rank, attendancePct;
  final bool isTop;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isTop
                  ? AppTheme.amber.withValues(alpha: 0.5)
                  : AppTheme.slate200),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color:
                    isTop ? const Color(0xFFFFF7ED) : AppTheme.primaryBg,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('#$rank',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isTop
                            ? const Color(0xFFEA580C)
                            : AppTheme.primary)),
              ),
            ),
            const SizedBox(width: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(fullName: entry.memberName, radius: 20),
                if (isTop)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.amber,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('TOP',
                          style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.memberName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  TeamBadge(team: entry.team),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$attendancePct%',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppTheme.primary)),
                Text('${entry.presentCount} pts',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.slate500)),
              ],
            ),
          ],
        ),
      );
}
