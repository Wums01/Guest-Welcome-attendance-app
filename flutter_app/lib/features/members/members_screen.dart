import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/member.dart';
import '../../models/enums.dart';
import '../../services/member_service.dart';
import '../../app_theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/team_badge.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final membersListProvider = FutureProvider<List<Member>>((ref) {
  return ref.read(memberServiceProvider).getMembers();
});

// ── MembersScreen ─────────────────────────────────────────────────────────────

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  final _search = TextEditingController();
  String _query = '';
  Team? _teamFilter; // null = All

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Member> _filter(List<Member> members) {
    var result = members;
    if (_teamFilter != null) {
      result = result.where((m) => m.team == _teamFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result.where((m) {
        return m.fullName.toLowerCase().contains(q) ||
            m.offlineCode.contains(q) ||
            m.phone.contains(q) ||
            m.team.value.toLowerCase().contains(q);
      }).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu, size: 22),
          onPressed: () => context.push('/settings'),
        ),
        title: const Text('Members'),
        actions: [
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Notifications coming soon'),
                duration: Duration(seconds: 2),
              ),
            ),
            child: Stack(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.notifications_outlined),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/members/new'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search members...',
                        prefixIcon: Icon(Icons.search,
                            size: 20, color: AppTheme.slate500),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Filter coming soon'),
                        duration: Duration(seconds: 2),
                      ),
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        border: Border.all(color: AppTheme.slate200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.tune,
                          size: 20, color: AppTheme.slate500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Team filter chips ─────────────────────────────────────────
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _TeamChip(
                    label: 'All',
                    selected: _teamFilter == null,
                    onTap: () => setState(() => _teamFilter = null),
                  ),
                  const SizedBox(width: 8),
                  ...Team.values.map((t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TeamChip(
                          label: t.value,
                          selected: _teamFilter == t,
                          onTap: () =>
                              setState(() => _teamFilter = t),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Member list ───────────────────────────────────────────────
            Expanded(
              child: membersAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error: $e')),
                data: (members) {
                  final filtered = _filter(members);
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No members found.',
                          style:
                              TextStyle(color: AppTheme.slate500)),
                    );
                  }
                  return RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: () async =>
                        ref.invalidate(membersListProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          16, 0, 16, 100),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) =>
                          _MemberCard(member: filtered[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _TeamChip ─────────────────────────────────────────────────────────────────

class _TeamChip extends StatelessWidget {
  const _TeamChip(
      {required this.label,
      required this.selected,
      required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color:
                  selected ? AppTheme.primary : AppTheme.slate200),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.slate500,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ── _MemberCard ───────────────────────────────────────────────────────────────

class _MemberCard extends ConsumerWidget {
  const _MemberCard({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/members/${member.id}'),
      child: Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          MemberAvatar(fullName: member.fullName, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TeamBadge(team: member.team),
                    const SizedBox(width: 8),
                    Text(
                      'Code: ${member.offlineCode}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.slate500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: AppTheme.error),
            onPressed: () => _confirmDelete(context, ref),
          ),
          const Icon(Icons.chevron_right,
              size: 20, color: AppTheme.slate500),
        ],
      ),
    ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete member?'),
        content: Text('Remove ${member.fullName}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(memberServiceProvider)
          .deleteMember(member.id);
      ref.invalidate(membersListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cannot delete: member has attendance records.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}
