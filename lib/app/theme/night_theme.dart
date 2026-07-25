import 'package:flutter/material.dart';

/// Used for alarm creation/editing and any other setup screen used at night.
/// Calm and low-contrast on purpose: not pure black, so it doesn't feel like
/// a jarring void in a dark room, but dim enough not to disturb sleep.
const _nightBackground = Color(0xFF0B0D10);
const _nightSurface = Color(0xFF15181D);

// Single strong accent, not specified in CLAUDE.md — chosen here as a calm
// teal that reads clearly against the near-black background.
const _nightAccent = Color(0xFF2FE6C4);

final ThemeData nightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _nightBackground,
  colorScheme: const ColorScheme.dark(
    surface: _nightSurface,
    primary: _nightAccent,
    secondary: _nightAccent,
  ),
);
