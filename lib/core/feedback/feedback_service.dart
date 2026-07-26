import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../haptics/haptics_service.dart';

const _tag = '[FeedbackService]';

/// Coordinates haptic + optional beep feedback as an OUTPUT of counting —
/// never a driver of it — per CLAUDE.md. No TTS.
class FeedbackService {
  FeedbackService({HapticsService? haptics}) : _haptics = haptics ?? HapticsService();

  final HapticsService _haptics;
  final AudioPlayer _beepPlayer = AudioPlayer();

  /// Haptic is always on; this only toggles the optional beep. Defaults to
  /// on for Phase 3 dev testing so reps are audible without watching the
  /// screen — flip off via the settings toggle later.
  bool beepEnabled = AppConfig.beepEnabledByDefault;

  Future<void> onValidRep({required bool isFinalStretch}) async {
    if (isFinalStretch) {
      await _haptics.finalStretchPulse();
    } else {
      await _haptics.repPulse();
    }
    if (beepEnabled) {
      unawaited(_playBeep());
    }
  }

  Future<void> onCompletion() async {
    await _haptics.completionPulse();
  }

  Future<void> _playBeep() async {
    try {
      await _beepPlayer.stop();
      await _beepPlayer.play(AssetSource('sounds/rep_beep.wav'));
    } catch (error) {
      debugPrint('$_tag beep playback FAILED: $error');
    }
  }

  void dispose() {
    _beepPlayer.dispose();
  }
}
