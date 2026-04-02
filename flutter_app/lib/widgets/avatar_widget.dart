import 'package:flutter/material.dart';
import '../app_theme/app_theme.dart';

/// Circular avatar showing a member's initials (or a photo if [imageUrl] is set).
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.fullName,
    this.imageUrl,
    this.radius = 24,
  });

  final String fullName;
  final String? imageUrl;
  final double radius;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isEmpty ? '?' : fullName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(imageUrl!),
        backgroundColor: AppTheme.primaryBg,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primaryBg,
      child: Text(
        _initials,
        style: TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.6,
        ),
      ),
    );
  }
}
