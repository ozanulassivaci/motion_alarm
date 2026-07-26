import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../haptics/haptics_service.dart';

const _tag = '[FeedbackService]';

/// Coordinates haptic + optional beep feedback as an OUTPUT of counting —
/// never a driver of it — per CLAUDE.md. No TTS.
class FeedbackService {
  FeedbackService({HapticsService? haptics}) : _haptics = haptics ?? HapticsService() {
    unawaited(_prepareBeep());
  }

  final HapticsService _haptics;
  final AudioPlayer _beepPlayer = AudioPlayer();
  bool _beepReady = false;

  /// Haptic is always on; this only toggles the optional beep. Defaults to
  /// on for Phase 3 dev testing so reps are audible without watching the
  /// screen — flip off via the settings toggle later.
  bool beepEnabled = AppConfig.beepEnabledByDefault;

  /// AudioPlayer.play() unconditionally calls setSource() internally on
  /// EVERY invocation — even with the same source — which redoes the full
  /// native setDataSource/prepareAsync dance each time. On top of that, the
  /// default ReleaseMode.release tears the native player down again the
  /// instant playback completes. Measured effect: a full native setup ->
  /// prepare -> play -> release -> finalize cycle per 90ms beep, stalling
  /// the pose pipeline (inference jumped from ~65ms to 100-170ms).
  ///
  /// Fix, per audioplayers' own docs: setSource() once here, with
  /// ReleaseMode.stop so a finished beep just stops instead of releasing —
  /// then _playBeep() below only ever calls seek()+resume(), which are
  /// cheap native calls that touch the already-prepared player.
  Future<void> _prepareBeep() async {
    try {
      await _beepPlayer.setReleaseMode(ReleaseMode.stop);
      await _beepPlayer.setSource(AssetSource('sounds/rep_beep.wav'));
      _beepReady = true;
    } catch (error) {
      debugPrint('$_tag beep preparation FAILED: $error');
    }
  }

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
    // Not prepared yet (still loading, very early after construction) —
    // skip rather than fall back to the slow play(source) path.
    if (!_beepReady) return;
    try {
      await _beepPlayer.seek(Duration.zero);
      await _beepPlayer.resume();
    } catch (error) {
      debugPrint('$_tag beep playback FAILED: $error');
    }
  }

  void dispose() {
    _beepPlayer.dispose();
  }
}
