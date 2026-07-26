import 'package:vibration/vibration.dart';

import '../config.dart';

/// Thin wrapper around the `vibration` package for the rep-feedback haptic
/// patterns described in CLAUDE.md. Capability checks (hasVibrator,
/// hasAmplitudeControl) are cached — the answer never changes for a given
/// device, so there's no reason to re-ask the platform every rep.
class HapticsService {
  bool? _hasVibrator;
  bool? _hasAmplitudeControl;

  Future<void> _ensureCapabilities() async {
    _hasVibrator ??= await Vibration.hasVibrator();
    _hasAmplitudeControl ??= await Vibration.hasAmplitudeControl();
  }

  /// Short pulse on each valid counted rep.
  Future<void> repPulse() async {
    await _ensureCapabilities();
    if (_hasVibrator != true) return;
    if (_hasAmplitudeControl == true) {
      Vibration.vibrate(duration: AppConfig.repHapticDurationMs, amplitude: 150);
    } else {
      Vibration.vibrate(duration: AppConfig.repHapticDurationMs);
    }
  }

  /// Distinct, heavier pulse for the last few reps before the target, to
  /// signal the finish line.
  Future<void> finalStretchPulse() async {
    await _ensureCapabilities();
    if (_hasVibrator != true) return;
    if (_hasAmplitudeControl == true) {
      Vibration.vibrate(
        duration: AppConfig.finalStretchHapticDurationMs,
        amplitude: 255,
      );
    } else {
      Vibration.vibrate(duration: AppConfig.finalStretchHapticDurationMs);
    }
  }

  /// Long success vibration on completing the full set.
  Future<void> completionPulse() async {
    await _ensureCapabilities();
    if (_hasVibrator != true) return;
    Vibration.vibrate(duration: AppConfig.completionHapticDurationMs);
  }
}
