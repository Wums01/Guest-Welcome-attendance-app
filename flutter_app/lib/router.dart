import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/logger.dart';
import 'features/auth/profile_picker_screen.dart';
import 'features/auth/staff_profile_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/celebrations_screen.dart';
import 'features/members/members_screen.dart';
import 'features/members/register_member_screen.dart';
import 'features/members/member_detail_screen.dart';
import 'features/programs/programs_screen.dart';
import 'features/programs/program_detail_screen.dart';
import 'features/sessions/sessions_screen.dart';
import 'features/sessions/session_detail_screen.dart';
import 'features/sessions/checkin_gate_screen.dart';
import 'features/attendance/offline_checkin_screen.dart';
import 'features/attendance/member_verification_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/settings/settings_screen.dart';
import 'providers/auth_provider.dart';
import 'widgets/bottom_nav_bar.dart';

// ---------------------------------------------------------------------------
// Router provider — rebuilds whenever auth state changes
// ---------------------------------------------------------------------------

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  final router = _buildRouter(ref, notifier);
  ref.onDispose(router.dispose);
  ref.onDispose(notifier.dispose);
  return router;
});

GoRouter _buildRouter(Ref ref, ChangeNotifier refreshListenable) {
  return GoRouter(
    initialLocation: '/',
    observers: [_RouterObserver()],
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(currentStaffProvider);

      // While session is being restored, don't redirect yet
      if (authState.isLoading) return null;

      final staff = authState.valueOrNull;
      final loc = state.matchedLocation;

      // Only '/' (profile picker) is accessible without a session
      if (staff == null && loc != '/') return '/'; // guard all other routes
      if (staff != null && loc == '/') return '/home'; // skip picker if authed
      return null;
    },
    routes: [
      // Profile picker — the unauthenticated landing screen
      GoRoute(
        path: '/',
        builder: (_, __) => const ProfilePickerScreen(),
      ),

      // Shell wraps all dashboard tabs with the bottom nav bar
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: '/members',
            builder: (_, __) => const MembersScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const RegisterMemberScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => MemberDetailScreen(
                  memberId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/programs',
            builder: (_, __) => const ProgramsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => ProgramDetailScreen(
                  programId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/sessions',
            builder: (_, __) => const SessionsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => SessionDetailScreen(
                  sessionId: state.pathParameters['id']!,
                ),
                routes: [
                  GoRoute(
                    path: 'checkin',
                    builder: (_, state) => CheckinGateScreen(
                      sessionId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'code',
                    builder: (_, state) => OfflineCheckinScreen(
                      sessionId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            builder: (_, __) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/celebrations',
            builder: (_, __) => const CelebrationsScreen(),
          ),
        ],
      ),

      // Settings is outside the bottom nav shell
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      // Profile is outside the bottom nav shell
      GoRoute(
        path: '/profile',
        builder: (_, __) => const StaffProfileScreen(),
      ),
      // Member verification screen (check-in success)
      GoRoute(
        path: '/verification',
        builder: (_, state) {
          final member = state.extra as Map<String, dynamic>?;
          if (member == null) {
            return const Scaffold(
              body: Center(child: Text('Invalid verification data')),
            );
          }
          return MemberVerificationScreen(
            member: member['member'],
            entryTime: member['entryTime'],
            status: member['status'],
            positionLabel: member['positionLabel'],
          );
        },
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Listenable that re-triggers GoRouter redirect on auth state changes
// ---------------------------------------------------------------------------

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue>(currentStaffProvider, (_, __) => notifyListeners());
  }
}

// ---------------------------------------------------------------------------
// Shell widget — holds the Scaffold + BottomNavBar shared by all tabs
// ---------------------------------------------------------------------------
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _tabs = [
    (label: 'Home', icon: Icons.home_outlined, route: '/home'),
    (label: 'Sessions', icon: Icons.calendar_today, route: '/sessions'),
    (label: 'Programs', icon: Icons.list_alt_outlined, route: '/programs'),
    (label: 'Members', icon: Icons.people_outline, route: '/members'),
    (label: 'Reports', icon: Icons.bar_chart, route: '/reports'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: index,
        tabs: _tabs.map((t) => NavTab(label: t.label, icon: t.icon)).toList(),
        onTap: (i) => context.go(_tabs[i].route),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NavigatorObserver — logs every push/pop/replace for debugging
// ---------------------------------------------------------------------------
class _RouterObserver extends NavigatorObserver {
  static const _tag = 'Router';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLogger.info(
      _tag,
      'push  ${_name(previousRoute)} → ${_name(route)}',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLogger.info(
      _tag,
      'pop   ${_name(route)} → ${_name(previousRoute)}',
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLogger.info(
      _tag,
      'replace ${_name(oldRoute)} → ${_name(newRoute)}',
    );
  }

  String _name(Route<dynamic>? route) =>
      route?.settings.name ?? route?.runtimeType.toString() ?? '(none)';
}
