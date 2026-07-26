import 'package:flutter/foundation.dart';

enum RepCounterPhase { seekingPeak, seekingTrough }

/// Why a completed peak-to-trough cycle didn't count as a rep. Both gates
/// only apply once a reversal has already been confirmed (see RepCounter's
/// doc comment) — they never block the reversal itself from being tracked.
enum RepRejectionReason { romGate, durationGate }

@immutable
class RepCounterUpdate {
  const RepCounterUpdate({
    required this.phase,
    required this.extremeValue,
    required this.lastConfirmedPeak,
    required this.lastConfirmedTrough,
    required this.repConfirmed,
    required this.rejectionReason,
  });

  final RepCounterPhase phase;
  final double extremeValue;
  final double? lastConfirmedPeak;
  final double? lastConfirmedTrough;

  /// True exactly on the update() call where a rep was counted.
  final bool repConfirmed;

  /// Set exactly on the update() call where a completed cycle was rejected.
  final RepRejectionReason? rejectionReason;
}

/// Exercise-agnostic rep-counting state machine, per CLAUDE.md's rule that
/// there is ONE such engine shared by every exercise.
///
/// Tracks a running local extreme (the max seen so far while
/// [RepCounterPhase.seekingPeak], the min while [RepCounterPhase.seekingTrough])
/// and confirms that extreme once the signal has retraced from it by more
/// than [minRepAmplitude] — a *relative reversal* gate, not a fixed absolute
/// threshold crossing. This is what stays robust at low, irregular frame
/// rates: it never needs to sample the signal AT a specific value, only
/// notice a clear reversal in trend, which survives large jumps between
/// sparse frames. There is deliberately no minimum-sample-count requirement
/// before a reversal can be confirmed — at ~8-10fps a fast rep may only
/// produce 1-2 samples near its true extreme, and requiring more would
/// systematically miss exactly the fast reps this design exists for.
///
/// A confirmed peak-trough cycle only counts as a rep if it also passes:
/// - [romGate]: the absolute peak-to-trough span, so a self-calibrating
///   reversal detector doesn't also count tiny bounces or quarter-reps.
/// - [minRepDurationMs]: wall-clock time between the two confirmed extrema,
///   so a cycle completed faster than physically plausible is rejected.
class RepCounter {
  RepCounter({
    required this.minRepAmplitude,
    required this.romGate,
    required this.minRepDurationMs,
  });

  final double minRepAmplitude;
  final double romGate;
  final int minRepDurationMs;

  RepCounterPhase _phase = RepCounterPhase.seekingPeak;
  bool _hasSample = false;
  double _extremeValue = 0;
  int _extremeTimestampMs = 0;

  double? _confirmedPeak;
  int? _confirmedPeakTimestampMs;
  double? _lastConfirmedTrough;

  int _repCount = 0;

  int get repCount => _repCount;

  /// Feeds one new sample of the exercise's metric() value in. [timestampMs]
  /// should be a monotonic clock reading (not wall-clock DateTime), matching
  /// whatever the caller uses consistently across calls.
  RepCounterUpdate update(double value, int timestampMs) {
    if (!_hasSample) {
      _hasSample = true;
      _extremeValue = value;
      _extremeTimestampMs = timestampMs;
      return _snapshot();
    }

    var repConfirmed = false;
    RepRejectionReason? rejectionReason;

    if (_phase == RepCounterPhase.seekingPeak) {
      if (value >= _extremeValue) {
        _extremeValue = value;
        _extremeTimestampMs = timestampMs;
      } else if (_extremeValue - value > minRepAmplitude) {
        // Peak confirmed: the signal has clearly turned back down.
        _confirmedPeak = _extremeValue;
        _confirmedPeakTimestampMs = _extremeTimestampMs;
        _phase = RepCounterPhase.seekingTrough;
        _extremeValue = value;
        _extremeTimestampMs = timestampMs;
      }
    } else {
      if (value <= _extremeValue) {
        _extremeValue = value;
        _extremeTimestampMs = timestampMs;
      } else if (value - _extremeValue > minRepAmplitude) {
        // Trough confirmed: the signal has clearly turned back up,
        // completing one full peak-trough cycle — a rep candidate.
        final trough = _extremeValue;
        final troughTimestampMs = _extremeTimestampMs;
        _lastConfirmedTrough = trough;

        final peak = _confirmedPeak;
        final peakTimestampMs = _confirmedPeakTimestampMs;
        if (peak != null && peakTimestampMs != null) {
          final rangeOfMotion = peak - trough;
          final durationMs = troughTimestampMs - peakTimestampMs;
          if (rangeOfMotion < romGate) {
            rejectionReason = RepRejectionReason.romGate;
          } else if (durationMs < minRepDurationMs) {
            rejectionReason = RepRejectionReason.durationGate;
          } else {
            repConfirmed = true;
            _repCount++;
          }
        }

        _phase = RepCounterPhase.seekingPeak;
        _extremeValue = value;
        _extremeTimestampMs = timestampMs;
      }
    }

    return _snapshot(repConfirmed: repConfirmed, rejectionReason: rejectionReason);
  }

  RepCounterUpdate _snapshot({
    bool repConfirmed = false,
    RepRejectionReason? rejectionReason,
  }) {
    return RepCounterUpdate(
      phase: _phase,
      extremeValue: _extremeValue,
      lastConfirmedPeak: _confirmedPeak,
      lastConfirmedTrough: _lastConfirmedTrough,
      repConfirmed: repConfirmed,
      rejectionReason: rejectionReason,
    );
  }
}
