import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app/theme/morning_theme.dart';
import '../exercise/workout_screen.dart';
import 'native_alarm_ring_bridge.dart';

/// Fires full-screen over the lock screen. Ringing itself (sound +
/// vibration) is owned entirely by the native AlarmRingService, independent
/// of this screen's lifecycle — see CLAUDE.md's "Alarm ownership"
/// architecture. This screen is only a view: "Egzersize Başla" lowers the
/// alarm's volume (it keeps ringing, quietly, through the whole workout —
/// tapping this is not a free snooze) and hands off to WorkoutScreen, which
/// owns everything from the framing check through dismissal, including the
/// emergency exit that's the only thing that actually stops the service.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({super.key, this.alarmId});

  final String? alarmId;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  final _ringBridge = NativeAlarmRingBridge();
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _startingExercise = false;

  @override
  void initState() {
    super.initState();
    ScreenBrightness().setApplicationScreenBrightness(1.0);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _startExercise() async {
    if (_startingExercise) return;
    _startingExercise = true;

    await _ringBridge.lowerVolume();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WorkoutScreen(alarmId: widget.alarmId)),
      );
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    // Brightness stays maxed — WorkoutScreen wants it too, and re-requests
    // it on its own init regardless of this screen's dispose(). Ringing
    // itself is untouched here: only stopRinging() (workout completion or
    // confirmed emergency exit) actually stops it.
    ScreenBrightness().resetApplicationScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeText = TimeOfDay.fromDateTime(_now).format(context);
    return Theme(
      data: morningTheme,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    timeText,
                    style: const TextStyle(
                      fontSize: 96,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 48),
                  FilledButton(
                    onPressed: _startExercise,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 24,
                      ),
                      textStyle: const TextStyle(fontSize: 24),
                    ),
                    child: const Text('Egzersize Başla'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
