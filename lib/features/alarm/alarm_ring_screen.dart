import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:vibration/vibration.dart';

import '../../app/theme/morning_theme.dart';
import '../home/home_screen.dart';
import 'alarm_list_controller.dart';

/// Fires full-screen over the lock screen. For now, "Alarmı Kapat" is a
/// trivial dismiss — the exercise flow will replace this button with the
/// actual rep-counting screen in a later phase, at which point a separate,
/// deliberately effortful emergency exit goes here too.
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

  // TODO: Once the exercise flow exists, this trivial dismiss is replaced by
  // completing the assigned exercise, and a deliberately effortful
  // (long-press + confirm) emergency exit is added alongside it.
  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;

    await _audioPlayer.stop();
    await Vibration.cancel();
    await ScreenBrightness().resetApplicationScreenBrightness();

    final alarmId = widget.alarmId;
    if (alarmId != null) {
      await ref
          .read(alarmListControllerProvider.notifier)
          .disableIfOneTime(alarmId);
    }

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
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
                  onPressed: _dismiss,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 24,
                    ),
                    textStyle: const TextStyle(fontSize: 24),
                  ),
                  child: const Text('Alarmı Kapat'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
