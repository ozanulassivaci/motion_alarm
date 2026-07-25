/// All detection- and timing-related magic numbers live here so they can be
/// tuned in one place without touching pipeline or widget code.
///
/// Values below are Phase 0 placeholders. They will be replaced with
/// measured defaults once the rep-counter engine is implemented.
class AppConfig {
  // --- Normalization ---

  // Minimum normalized torso length (as a fraction of frame height) below
  // which pose measurements are considered too small/unreliable to trust.
  static const double minNormalizedTorsoLength = 0.05;

  // --- Hysteresis (RepCounter state machine) ---

  // A metric must fall below this normalized value to enter the DOWN state.
  static const double hysteresisEnterDownThreshold = 0.35;

  // A metric must rise above this normalized value to return to the UP state.
  // Must stay lower than hysteresisEnterDownThreshold to create a dead zone
  // that prevents jitter from double-counting a rep.
  static const double hysteresisExitUpThreshold = 0.55;

  // --- Rep validity rules ---

  // Shortest allowed time (ms) between a DOWN and UP transition. Rejects
  // reps completed faster than is physically plausible (sensor noise).
  static const int minRepDurationMs = 300;

  // Minimum normalized amplitude a metric must swing through between DOWN
  // and UP to count as a real rep rather than small jitter.
  static const double minRepAmplitude = 0.15;

  // Minimum ML Kit landmark visibility/confidence score required before a
  // landmark is trusted for metric computation.
  static const double minLandmarkVisibility = 0.6;

  // --- Framing / calibration timing ---

  // Countdown (seconds) shown on the framing-check screen once the user is
  // correctly positioned, before rep counting begins.
  static const int countdownSeconds = 3;

  // Duration (seconds) of the "stand still" capture used to record the
  // user's personal calibration reference (torso length, resting hip height).
  static const int calibrationSeconds = 3;
}
