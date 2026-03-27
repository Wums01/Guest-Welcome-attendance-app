// lib/providers/theme_provider.dart
//
// Manages app brightness (light/dark mode).
// Persists user's theme preference in SharedPreferences.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_logger.dart';

const _tag = 'ThemeProvider';
const _brightnessKey = 'app_brightness';

/// Provider for app brightness (light/dark mode)
final brightnessProvider =
    StateNotifierProvider<BrightnessNotifier, Brightness>((ref) {
  return BrightnessNotifier();
});

/// Notifier for managing brightness state
class BrightnessNotifier extends StateNotifier<Brightness> {
  BrightnessNotifier() : super(Brightness.light) {
    _loadBrightness();
  }

  /// Load the saved brightness preference from SharedPreferences
  Future<void> _loadBrightness() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_brightnessKey);

      if (saved != null) {
        state = saved == 'dark' ? Brightness.dark : Brightness.light;
        AppLogger.debug(
          'Loaded brightness preference: ${state.name}',
          tag: _tag,
        );
      } else {
        // Default to light mode
        state = Brightness.light;
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to load brightness preference',
        tag: _tag,
        error: e,
        stack: s,
      );
      state = Brightness.light;
    }
  }

  /// Toggle brightness between light and dark
  Future<void> toggle() async {
    final newBrightness =
        state == Brightness.light ? Brightness.dark : Brightness.light;
    state = newBrightness;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _brightnessKey,
        newBrightness == Brightness.dark ? 'dark' : 'light',
      );
      AppLogger.debug(
        'Brightness changed to: ${newBrightness.name}',
        tag: _tag,
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to save brightness preference',
        tag: _tag,
        error: e,
        stack: s,
      );
    }
  }

  /// Set brightness to a specific value
  Future<void> setBrightness(Brightness brightness) async {
    state = brightness;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _brightnessKey,
        brightness == Brightness.dark ? 'dark' : 'light',
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to save brightness preference',
        tag: _tag,
        error: e,
        stack: s,
      );
    }
  }
}
