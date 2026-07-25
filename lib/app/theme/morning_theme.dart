import 'package:flutter/material.dart';

/// Used while the alarm rings and during the exercise flow: bright and
/// high-contrast so a half-asleep user can read it from 2 meters away, and
/// max screen brightness is requested separately when this theme is active.
const _morningBackground = Color(0xFFFAFAFA);

// Kept in sync with the night theme's accent so the "success" moment reads
// as the same brand color across both themes.
const _morningAccent = Color(0xFF00B89C);

final ThemeData morningTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: _morningBackground,
  colorScheme: const ColorScheme.light(
    surface: _morningBackground,
    primary: _morningAccent,
    secondary: _morningAccent,
  ),
);
