// lib/widgets/offline_indicator.dart
//
// Visual indicator showing offline status and pending sync count.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme/app_theme.dart';
import '../providers/offline_provider.dart';

class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOfflineAsync = ref.watch(isOfflineProvider);
    final pendingCountAsync = ref.watch(pendingClockInsCountProvider);

    return isOfflineAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (isOffline) {
        if (!isOffline) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.amber.withValues(alpha: 0.15),
            border: Border.all(color: AppTheme.amber),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: AppTheme.amber, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Offline',
                style: TextStyle(
                  color: AppTheme.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (pendingCountAsync.hasValue && pendingCountAsync.value! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${pendingCountAsync.value} pending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]
            ],
          ),
        );
      },
    );
  }
}
