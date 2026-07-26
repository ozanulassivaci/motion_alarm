import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// All detection- and timing-related magic numbers live here so they can be
/// tuned in one place without touching pipeline or widget code.
///
/// The rep-counter/ROM-gate values are reasoned starting defaults, not
/// measured ones — tune them against your own body using the dev screen's
/// debug overlay.
class AppConfig {
  // --- Normalization ---

  // Minimum normalized torso length (as a fraction of frame height) below
  // which pose measurements are considered too small/unreliable to trust.
  static const double minNormalizedTorsoLength = 0.05;

  // --- Rep-counter engine (extrema-reversal design) ---
  //
  // RepCounter tracks a running local extreme (max while SEEKING_PEAK, min
  // while SEEKING_TROUGH) and confirms that extreme once the signal has
  // retraced from it by more than minRepAmplitude — a *relative* reversal
  // gate, not a fixed absolute threshold. This is what stays robust at
  // ~8-10fps: it never needs to sample the signal at a specific value, only
  // notice a clear reversal in trend, which survives large jumps between
  // sparse frames. See core/rep_counter.dart.

  // Minimum normalized amplitude a metric must swing through, from its
  // running extreme, before that extreme is confirmed as a real peak/trough
  // rather than jitter. Also the minimum swing for the OLD fixed-threshold
  // design this replaced; kept as one shared "how much wobble is noise"
  // constant.
  static const double minRepAmplitude = 0.15;

  // Shortest allowed time (ms) between a confirmed peak and the confirmed
  // trough that completes it. Rejects reps completed faster than is
  // physically plausible (sensor noise), checked in wall-clock time between
  // the two confirmed extrema — not frame count, so it stays meaningful
  // regardless of fps.
  static const int minRepDurationMs = 300;

  // --- Range-of-motion gates ---
  //
  // Extrema-reversal alone is self-calibrating: a user doing shallow
  // quarter-squats or a small bounce would still confirm peaks/troughs and
  // get reps counted. Each gate below rejects a confirmed peak-to-trough
  // cycle whose absolute span is too small, even though the reversal itself
  // was real. Each is expressed as a *fraction of a calibration reference*
  // (leg length or torso length — see calibration.dart), so the fraction is
  // the fixed tunable constant while the actual distance required scales to
  // the user's own body. These are starting guesses reasoned from typical
  // body proportions — tune them against your own body using the dev
  // screen's debug overlay, which shows "ROM gate" as the rejection reason
  // when a real movement was too shallow to count.

  // Squat: hip drop must be at least this fraction of leg length. ~15% of
  // an ~85cm leg is ~13cm — clearly more than standing sway, well short of
  // a "deep" squat, so shallow-but-real squats still count.
  static const double squatRomGate = 0.15;

  // Jumping jack, ankle-spread sub-metric: ankle distance must swing by at
  // least this fraction of shoulder width. Resting stance is roughly
  // hip-width apart (~0.3-0.6x shoulder width); a real jack spread roughly
  // doubles that, so 0.5 requires a clear spread, not a small shuffle.
  static const double jumpingJackAnkleRomGate = 0.5;

  // Jumping jack, wrist-height sub-metric: wrist height must swing by at
  // least this fraction of torso length. Raising arms to shoulder height as
  // part of a jack already covers a large fraction of torso length, so 0.4
  // requires a genuine raise without demanding a full overhead extension.
  static const double jumpingJackWristRomGate = 0.4;

  // High knees: knee height must rise by at least this fraction of leg
  // length above its calibrated resting position. ~25% of an ~85cm leg is
  // ~21cm — a deliberate lift, clearly more than normal walking-in-place
  // jitter, well short of a knee-to-hip "extreme" lift.
  static const double highKneeRomGate = 0.25;

  // Overhead reach: wrist height must rise by at least this fraction of
  // torso length above the nose line. Going from arms-at-sides to fully
  // overhead spans well over a full torso length, so 0.3 is a conservative
  // minimum that still requires real overhead extension, not a
  // shoulder-height raise.
  static const double overheadReachRomGate = 0.3;

  // --- Jumping jack: independent sub-metric alignment ---

  // Jumping jack has two independently-tracked sub-metrics (ankle spread,
  // wrist height); a combined rep counts only when both confirm their
  // "closed" trough within this many ms of each other — not the same video
  // frame, since sparse sampling makes exact-frame coincidence unlikely
  // even for a well-synchronized jack.
  static const int jumpingJackAlignmentWindowMs = 300;

  // --- Feedback ---

  // Whether the optional rep-counted beep defaults to on. On for Phase 3
  // dev testing, so reps are audible without watching the screen; the
  // settings toggle can turn it off later.
  static const bool beepEnabledByDefault = true;

  // Haptic pulse duration (ms) for a normal counted rep.
  static const int repHapticDurationMs = 40;

  // Haptic pulse duration (ms) for each of the last few reps before the
  // target, to signal the finish line.
  static const int finalStretchHapticDurationMs = 120;

  // How many reps before the target switch to the heavier "finish line"
  // haptic.
  static const int finalStretchRepCount = 3;

  // Long success vibration duration (ms) on completing the full set.
  static const int completionHapticDurationMs = 800;

  // Default target rep count for the dev screen's test sessions, matching
  // CLAUDE.md's Easy-difficulty default (1 exercise x 8 reps).
  static const int defaultTargetReps = 8;

  // Minimum ML Kit landmark visibility/confidence score required before a
  // landmark is trusted — both for rep-metric computation and for the
  // framing-check's "is this landmark actually visible" test.
  static const double minLandmarkVisibility = 0.6;

  // --- Framing / calibration timing ---

  // Countdown (seconds) shown on the framing-check screen once the user is
  // correctly positioned, before rep counting begins.
  static const int countdownSeconds = 3;

  // Duration (seconds) of the "stand still" capture used to record the
  // user's personal calibration reference (torso length, resting hip height).
  static const int calibrationSeconds = 3;

  // --- Camera / pose pipeline ---

  // ~240p on Android. Pose landmarks are robust at low resolution. Measured
  // on a Galaxy A25: this did NOT reduce ML Kit inference time (ML Kit
  // resizes to its own fixed input size internally regardless of what we
  // feed it), but it does shrink the per-frame NV21 buffer the camera plugin
  // allocates and marshals to Dart on every captured frame.
  static const cameraResolutionPreset = ResolutionPreset.low;

  // Caps the camera's own capture rate at the source (passed straight to
  // CameraX's ImageAnalysis use case), instead of only dropping already-
  // captured frames in Dart. Measured root cause of GC pressure: the camera
  // plugin converts every captured frame from YUV_420_888 to NV21 natively
  // (allocating a fresh buffer) before it ever reaches Dart, regardless of
  // whether we go on to process or drop it — capping capture fps to roughly
  // what we can actually consume (given ~65ms inference) halves that native
  // conversion+allocation work instead of just discarding its output.
  static const int cameraCaptureFps = 15;

  // Whether to downscale the camera frame ourselves before handing it to
  // ML Kit. Measured on a Galaxy A25: this did NOT reduce inference time —
  // ML Kit resizes internally to its own fixed input size regardless of
  // what we feed it, so inference is a hardware floor (~65ms on this chip),
  // not a preprocessing cost. Left in place (off by default) in case a
  // future device's ML Kit build behaves differently.
  static const bool enableManualDownscale = false;

  // Integer factor applied to both width and height (2 = quarter the pixel
  // count). Must evenly divide the camera frame's dimensions.
  static const int manualDownscaleFactor = 2;

  // Landmarks that must all be visible for "whole body in frame" to be true.
  static const List<PoseLandmarkType> requiredFramingLandmarks = [
    PoseLandmarkType.nose,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  ];

  // Minimum time between pose-detector invocations, so a fast device doesn't
  // burn battery/heat running inference on every single camera frame when
  // ~15fps is already plenty for framing feedback. Frames arriving sooner
  // than this are dropped, not queued.
  static const int poseDetectionMinIntervalMs = 66;
}
