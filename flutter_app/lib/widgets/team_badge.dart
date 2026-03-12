import 'package:flutter/material.dart';
import '../app_theme/app_theme.dart';
import '../models/enums.dart';

/// Coloured pill badge for a member's team assignment.
class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    final (bg, text) = switch (team) {
      Team.teamA => (AppTheme.teamABg, AppTheme.teamAText),
      Team.teamB => (AppTheme.teamBBg, AppTheme.teamBText),
      Team.teamC => (AppTheme.teamCBg, AppTheme.teamCText),
      Team.none  => (AppTheme.teamNoneBg, AppTheme.teamNoneText),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        team.value.toUpperCase(),
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
