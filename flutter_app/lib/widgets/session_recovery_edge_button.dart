import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme/app_theme.dart';
import '../core/utils/date_utils.dart';
import '../services/session_service.dart';

class SessionRecoveryEdgeButton extends ConsumerStatefulWidget {
  const SessionRecoveryEdgeButton({super.key});

  @override
  ConsumerState<SessionRecoveryEdgeButton> createState() =>
      _SessionRecoveryEdgeButtonState();
}

class _SessionRecoveryEdgeButtonState
    extends ConsumerState<SessionRecoveryEdgeButton> {
  static const double _collapsedSize = 56;
  static const double _expandedHeight = 176;
  static const double _edgePadding = 12;
  static const double _topPadding = 96;
  static const double _bottomPadding = 116;

  bool _expanded = false;
  bool _running = false;
  bool _dockedRight = false;
  double? _top;
  Timer? _collapseTimer;

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  bool get _isSupportedDay {
    final weekday = nowInLagos().weekday;
    return weekday == DateTime.wednesday || weekday == DateTime.sunday;
  }

  DateTime get _nextSupportedDate {
    final now = nowInLagos();
    for (int offset = 1; offset <= 7; offset++) {
      final candidate = now.add(Duration(days: offset));
      if (candidate.weekday == DateTime.wednesday ||
          candidate.weekday == DateTime.sunday) {
        return DateTime(candidate.year, candidate.month, candidate.day);
      }
    }
    return DateTime(now.year, now.month, now.day);
  }

  String get _dayLabel {
    final weekday = nowInLagos().weekday;
    if (weekday == DateTime.sunday) return 'Sunday';
    if (weekday == DateTime.wednesday) return 'Wednesday';
    return 'Today';
  }

  String get _headline => _isSupportedDay ? 'Recover today\'s sessions' : 'Auto schedule info';

  String get _subtext => _isSupportedDay
      ? 'Use only if the automatic $_dayLabel session creation did not happen.'
      : 'Next automatic session generation is ${_formatNextSupportedDate()}.';

  String get _buttonLabel =>
      _isSupportedDay ? 'Run recovery' : 'Got it';

  Future<void> _runRecovery() async {
    if (_running) return;

    if (!_isSupportedDay) {
      _showMessage(
        'This recovery tool only runs on Sunday or Wednesday. Next automatic generation is ${_formatNextSupportedDate()}.',
      );
      setState(() => _expanded = true);
      _scheduleCollapse();
      return;
    }

    setState(() => _running = true);
    try {
      final today = formatDateISO(nowInLagos());
      final generatedCount = await ref
          .read(sessionServiceProvider)
          .generateWeeklySessionsForDate(today);

      if (!mounted) return;
      _showMessage(
        generatedCount > 0
            ? 'Created $generatedCount session${generatedCount == 1 ? '' : 's'} for $_dayLabel.'
            : 'No missing $_dayLabel sessions were found.',
      );
      setState(() => _expanded = false);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Session recovery failed: $e', isError: true);
      setState(() => _expanded = true);
    } finally {
      if (mounted) {
        setState(() => _running = false);
        _scheduleCollapse();
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.primary,
      ),
    );
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _scheduleCollapse();
    } else {
      _collapseTimer?.cancel();
    }
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_running) {
        setState(() => _expanded = false);
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details, Size size) {
    final currentTop = _resolvedTop(size);
    final panelHeight = _expanded ? _expandedHeight : _collapsedSize;
    final nextTop = _clampTop(currentTop + details.delta.dy, size, panelHeight);
    final centerX = _resolvedLeft(size) + (_panelWidth(size) / 2) + details.delta.dx;
    final half = size.width / 2;

    setState(() {
      _top = nextTop;
      _dockedRight = centerX >= half;
    });
  }

  void _onDragEnd(Size size) {
    setState(() {
      _top = _clampTop(_resolvedTop(size), size, _expanded ? _expandedHeight : _collapsedSize);
    });
    _scheduleCollapse();
  }

  double _panelWidth(Size size) =>
      _expanded ? math.min(212, size.width - (_edgePadding * 2)) : _collapsedSize;

  double _resolvedTop(Size size) {
    final fallback = size.height * 0.3;
    return _clampTop(
      _top ?? fallback,
      size,
      _expanded ? _expandedHeight : _collapsedSize,
    );
  }

  double _resolvedLeft(Size size) {
    final width = _panelWidth(size);
    if (_dockedRight) {
      return size.width - width - _edgePadding;
    }
    return _edgePadding;
  }

  double _clampTop(double value, Size size, double panelHeight) {
    const minTop = _topPadding;
    final maxTop = math.max(minTop, size.height - panelHeight - _bottomPadding);
    return value.clamp(minTop, maxTop);
  }

  String _formatNextSupportedDate() {
    final next = _nextSupportedDate;
    return '${_weekdayName(next.weekday)}, ${next.day.toString().padLeft(2, '0')}/${next.month.toString().padLeft(2, '0')}';
  }

  String _weekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Today';
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final top = _resolvedTop(size);
    final left = _resolvedLeft(size);
    final panelWidth = _panelWidth(size);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      top: top,
      left: left,
      child: GestureDetector(
        onPanUpdate: (details) => _onDragUpdate(details, size),
        onPanEnd: (_) => _onDragEnd(size),
        child: Container(
          width: panelWidth,
          constraints: BoxConstraints(
            minHeight: _collapsedSize,
            maxWidth: panelWidth,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(_expanded ? 24 : 999),
            border: Border.all(
              color: _isSupportedDay
                  ? AppTheme.primary.withValues(alpha: 0.22)
                  : AppTheme.slate200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _expanded
              ? Material(
                  color: Colors.transparent,
                  child: _buildExpandedCard(),
                )
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _toggleExpanded,
                    borderRadius: BorderRadius.circular(999),
                    child: _buildCollapsedOrb(),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCollapsedOrb() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.sync_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.sync_rounded,
                  color: AppTheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleExpanded,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBg,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.primary,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isSupportedDay
                ? 'Sunday/Wednesday fallback'
                : 'Next scheduled auto-run',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _subtext,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.slate500,
                fontSize: 10.5,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Drag to reposition',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.slate500,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton(
              onPressed: _running ? null : _runRecovery,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _buttonLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
