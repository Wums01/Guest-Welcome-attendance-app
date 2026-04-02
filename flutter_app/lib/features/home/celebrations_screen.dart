// lib/features/home/celebrations_screen.dart
//
// Shows members with upcoming birthdays and anniversaries (within 30 days)
// AND those celebrating today.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme/app_theme.dart';
import '../../models/member.dart';
import '../../core/utils/date_utils.dart';
import '../members/members_screen.dart'; // membersListProvider

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CelebrationsScreen extends ConsumerWidget {
  const CelebrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Birthdays & Anniversaries'),
        centerTitle: false,
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (members) {
          final today = nowInLagos();
          final todayMMDD = formatMMDD(today);

          // Build entries with their "days until" value
          final entries = <_CelebEntry>[];
          for (final m in members) {
            // Birthday — today or within 30 days
            if (m.birthdayMD == todayMMDD ||
                isWithinDays(m.birthdayMD, 30)) {
              entries.add(_CelebEntry(
                member: m,
                type: _Type.birthday,
                daysUntil: m.birthdayMD == todayMMDD
                    ? 0
                    : _daysUntil(m.birthdayMD, today),
              ));
            }
            // Anniversary — only if married and set
            final anniv = m.anniversaryMD;
            if (anniv != null &&
                (anniv == todayMMDD || isWithinDays(anniv, 30))) {
              entries.add(_CelebEntry(
                member: m,
                type: _Type.anniversary,
                daysUntil: anniv == todayMMDD ? 0 : _daysUntil(anniv, today),
              ));
            }
          }

          // Sort: today first, then by days ascending, then by name
          entries.sort((a, b) {
            final d = a.daysUntil.compareTo(b.daysUntil);
            if (d != 0) return d;
            return a.member.fullName.compareTo(b.member.fullName);
          });

          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No upcoming birthdays or anniversaries\nin the next 30 days.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 15),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: entries.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72, endIndent: 16),
            itemBuilder: (_, i) => _CelebTile(entry: entries[i], today: todayMMDD),
          );
        },
      ),
    );
  }

  int _daysUntil(String mmdd, DateTime today) {
    final parts = mmdd.split('-');
    var target = DateTime(
        today.year, int.parse(parts[0]), int.parse(parts[1]));
    if (target.isBefore(DateTime(today.year, today.month, today.day))) {
      target = DateTime(today.year + 1, target.month, target.day);
    }
    return target
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }
}

// ---------------------------------------------------------------------------
// Data helpers
// ---------------------------------------------------------------------------

enum _Type { birthday, anniversary }

class _CelebEntry {
  const _CelebEntry({
    required this.member,
    required this.type,
    required this.daysUntil,
  });
  final Member member;
  final _Type type;
  final int daysUntil;
}

// ---------------------------------------------------------------------------
// Tile
// ---------------------------------------------------------------------------

class _CelebTile extends StatelessWidget {
  const _CelebTile({required this.entry, required this.today});
  final _CelebEntry entry;
  final String today;

  @override
  Widget build(BuildContext context) {
    final member = entry.member;
    final isToday = entry.daysUntil == 0;
    final isBirthday = entry.type == _Type.birthday;

    final emoji = isBirthday ? '🎂' : '💍';
    final accentColor = isBirthday ? AppTheme.primary : AppTheme.amber;

    final sublabel = isToday
        ? 'Today!'
        : '${isBirthday ? 'Birthday' : 'Anniversary'} in ${entry.daysUntil} day${entry.daysUntil == 1 ? '' : 's'}';

    final initials = member.fullName
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: accentColor.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.fullName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accentColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Today',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            _TeamBadge(member),
            const SizedBox(width: 8),
            Text(
              sublabel,
              style: TextStyle(
                color: isToday ? accentColor : Colors.black54,
                fontSize: 12,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamBadge extends StatelessWidget {
  const _TeamBadge(this.member);
  final Member member;

  @override
  Widget build(BuildContext context) {
    Color bg, text;
    switch (member.team) {
      case _ when member.team.value == 'Team A':
        bg = AppTheme.teamABg;
        text = AppTheme.teamAText;
      case _ when member.team.value == 'Team B':
        bg = AppTheme.teamBBg;
        text = AppTheme.teamBText;
      case _ when member.team.value == 'Team C':
        bg = AppTheme.teamCBg;
        text = AppTheme.teamCText;
      default:
        bg = AppTheme.teamNoneBg;
        text = AppTheme.teamNoneText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        member.team.value,
        style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
