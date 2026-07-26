import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app/app.dart';
import '../../app/theme/morning_theme.dart';
import '../../data/models/alarm.dart';
import '../exercise/workout_screen.dart';
import 'alarm_list_controller.dart';
import 'native_alarm_ring_bridge.dart';

/// Fires full-screen over the lock screen. Ringing itself (sound +
/// vibration) is owned entirely by the native AlarmRingService, independent
/// of this screen's lifecycle — see CLAUDE.md's "Alarm ownership"
/// architecture. This screen is only a view: "Egzersize Başla" lowers the
/// alarm's volume and stops its vibration loop (the sound keeps ringing,
/// quietly, through the whole workout — tapping this is not a free snooze)
/// and hands off to WorkoutScreen, which owns everything from the framing
/// check through dismissal, including the emergency exit that's the only
/// thing that actually stops the service.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({super.key, this.alarmId});

  final String? alarmId;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  final _ringBridge = NativeAlarmRingBridge();
  // The scheduled alarm time, not the live clock — that's what a woken user
  // expects to see. Defaults to now() so there's never a blank frame;
  // overwritten once the matching Alarm (if any) is looked up.
  TimeOfDay _alarmTime = TimeOfDay.now();
  bool _startingExercise = false;

  @override
  void initState() {
    super.initState();
    isAlarmFlowActive = true;
    ScreenBrightness().setApplicationScreenBrightness(1.0);
    // Asserts "ring state" every time this screen is shown — a no-op if the
    // service was already ringing at full volume/vibration, but correctly
    // restores both if the exercise flow was previously entered and then
    // abandoned/interrupted (see AlarmRingService.setExerciseActive).
    _ringBridge.setExerciseActive(false);
    _loadAlarmTime();
  }

  Future<void> _loadAlarmTime() async {
    final id = widget.alarmId;
    if (id == null) return;
    final alarms = await ref.read(alarmListControllerProvider.future);
    Alarm? alarm;
    for (final candidate in alarms) {
      if (candidate.id == id) {
        alarm = candidate;
        break;
      }
    }
    // No match (deleted alarm, or the dev test-alarm's synthetic payload,
    // which has no fixed hour/minute at all) — current time is the only
    // reasonable fallback and stays as already set.
    if (alarm != null && mounted) {
      setState(() => _alarmTime = TimeOfDay(hour: alarm!.hour, minute: alarm.minute));
    }
  }

  Future<void> _startExercise() async {
    if (_startingExercise) return;
    _startingExercise = true;

    await _ringBridge.setExerciseActive(true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WorkoutScreen(alarmId: widget.alarmId)),
      );
    }
  }

  @override
  void dispose() {
    // Brightness stays maxed — WorkoutScreen wants it too, and re-requests
    // it on its own init regardless of this screen's dispose(). Ringing
    // itself is untouched here: only stopRinging() (workout completion or
    // confirmed emergency exit) actually stops it, and isAlarmFlowActive is
    // only cleared by that same shared exit path (see app.dart), not here.
    ScreenBrightness().resetApplicationScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeText = _alarmTime.format(context);
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
