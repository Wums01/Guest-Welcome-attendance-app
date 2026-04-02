// lib/widgets/stat_card.dart
//
// A single attendance stat tile (Present / Unmarked / Total).
// Used on HomScreen and ReportsScreen.

import 'package:flutter/material.dart';
import '../app_theme/app_theme.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurfaceContainerHigh
            : const Color(0xFFF8FAFC), // slate-50
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: valueColor
                  ?? (isDark ? AppTheme.darkPrimary : AppTheme.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppTheme.darkOnSurfaceVariant
                  : const Color(0xFF475569), // slate-600
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
