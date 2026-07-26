import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:vibration/vibration.dart';

import '../../app/theme/morning_theme.dart';
import '../exercise/workout_screen.dart';

/// Fires full-screen over the lock screen. "Egzersize Başla" stops the
/// alarm sound/vibration (so it doesn't collide with rep feedback, per
/// CLAUDE.md) and hands off to WorkoutScreen, which owns everything from
/// the framing check through dismissal — including the emergency exit.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({super.key, this.alarmId});

  final String? alarmId;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  final _audioPlayer = AudioPlayer();
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _startRinging();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _startRinging() async {
    await ScreenBrightness().setApplicationScreenBrightness(1.0);

    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/alarm.wav'));

    if (await Vibration.hasVibrator()) {
      // Vibrate immediately, then repeat the 800ms-on/400ms-off segment
      // (index 1 onward) until cancelled.
      Vibration.vibrate(pattern: [0, 800, 400], repeat: 1);
    }
  }

  Future<void> _startExercise() async {
    if (_dismissing) return;
    _dismissing = true;

    // Stops here so it doesn't collide with rep feedback, per CLAUDE.md.
    // Brightness stays maxed — WorkoutScreen wants it too, and re-requests
    // it on its own init regardless of this screen's dispose().
    await _audioPlayer.stop();
    await Vibration.cancel();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WorkoutScreen(alarmId: widget.alarmId)),
      );
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _audioPlayer.dispose();
    Vibration.cancel();
    ScreenBrightness().resetApplicationScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeText = TimeOfDay.fromDateTime(_now).format(context);
    return Theme(
      data: morningTheme,
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
    );
  }
}
