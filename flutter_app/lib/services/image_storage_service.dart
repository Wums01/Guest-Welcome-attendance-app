// lib/services/image_storage_service.dart
//
// Handles uploading member photos to Supabase Storage.
// Photos are stored in the 'member-photos' bucket.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_logger.dart';

const _tag = 'ImageStorageService';
const _bucket = 'member-photos';

/// Provider for ImageStorageService
final imageStorageServiceProvider = Provider((ref) => ImageStorageService());

/// Service for uploading and managing member photos.
class ImageStorageService {
  ImageStorageService();

  final _client = Supabase.instance.client;

  /// Upload a member photo to Supabase Storage.
  /// Returns the public URL of the uploaded photo.
  ///
  /// Throws an exception if upload fails.
  Future<String> uploadMemberPhoto({
    required String memberId,
    required File imageFile,
  }) async {
    try {
      AppLogger.info(
        '📸 UPLOAD START: member=$memberId, file=${imageFile.path}, size=${imageFile.lengthSync()} bytes',
        tag: _tag,
      );

      // Generate a unique filename: member-<id>-<timestamp>.jpg
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'member-$memberId-$timestamp.jpg';

      // Upload to Supabase Storage
      final path = 'members/$fileName';
      AppLogger.debug(
        '📤 Uploading to bucket: $_bucket, path: $path',
        tag: _tag,
      );

      await _client.storage.from(_bucket).upload(
            path,
            imageFile,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      AppLogger.info(
        '✓ File uploaded successfully to: $path',
        tag: _tag,
      );

      // Get the public URL
      final publicUrl =
          _client.storage.from(_bucket).getPublicUrl(path);

      AppLogger.info(
        '✓ PUBLIC URL: $publicUrl',
        tag: _tag,
      );
      return publicUrl;
    } catch (e, s) {
      AppLogger.error(
        '❌ UPLOAD FAILED for member $memberId: $e',
        tag: _tag,
        error: e,
        stack: s,
      );
      rethrow;
    }
  }

  /// Delete a member's photo from storage.
  Future<void> deleteMemberPhoto({required String photoUrl}) async {
    try {
      // Extract file path from public URL
      // URL format: https://<project>.supabase.co/storage/v1/object/public/member-photos/members/<filename>
      final uri = Uri.parse(photoUrl);
      final pathSegments = uri.pathSegments;

      // Find the index of 'members' and construct the path
      final memberIndex = pathSegments.indexOf('members');
      if (memberIndex == -1) {
        AppLogger.warn(
          'Could not extract path from photo URL: $photoUrl',
          tag: _tag,
        );
        return;
      }

      final filePath = pathSegments.sublist(memberIndex).join('/');

      await _client.storage.from(_bucket).remove([filePath]);

      AppLogger.debug(
        'Photo deleted successfully: $filePath',
        tag: _tag,
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to delete photo',
        tag: _tag,
        error: e,
        stack: s,
      );
      // Don't rethrow — deletion failure shouldn't block member operations
    }
  }
}
