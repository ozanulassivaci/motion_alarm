import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/config.dart';

/// Personal reference recorded once per session from the 3-second
/// "stand still" capture. All rep metrics and range-of-motion gates are
/// expressed relative to this, never raw pixels, per CLAUDE.md.
class CalibrationReference {
  const CalibrationReference({
    required this.torsoLength,
    required this.shoulderWidth,
    required this.legLength,
    required this.standingHipY,
    required this.restingKneeY,
  });

  /// Shoulder-midpoint to hip-midpoint distance while standing.
  final double torsoLength;

  /// Left-to-right shoulder distance while standing.
  final double shoulderWidth;

  /// Hip-to-ankle distance, averaged across both legs, while standing.
  final double legLength;

  /// Average hip Y position while standing — the squat metric's baseline.
  final double standingHipY;

  /// Average knee Y position while standing — the high-knees metric's
  /// baseline.
  final double restingKneeY;
}

const _requiredLandmarks = [
  PoseLandmarkType.leftShoulder,
  PoseLandmarkType.rightShoulder,
  PoseLandmarkType.leftHip,
  PoseLandmarkType.rightHip,
  PoseLandmarkType.leftKnee,
  PoseLandmarkType.rightKnee,
  PoseLandmarkType.leftAnkle,
  PoseLandmarkType.rightAnkle,
];

double _distance(PoseLandmark a, PoseLandmark b) => _distanceXY(a.x, a.y, b.x, b.y);

double _distanceXY(double x1, double y1, double x2, double y2) {
  final dx = x1 - x2;
  final dy = y1 - y2;
  return sqrt(dx * dx + dy * dy);
}

/// Accumulates samples over the 3-second "stand still" window and produces
/// a [CalibrationReference] once complete. Only wall-clock time between
/// consecutive *valid* samples counts toward the window, so stepping out of
/// frame partway through doesn't get silently credited as holding still.
class CalibrationCapture {
  CalibrationCapture({int? requiredMs})
    : _requiredMs = requiredMs ?? AppConfig.calibrationSeconds * 1000;

  final int _requiredMs;

  int _validElapsedMs = 0;
  int? _lastSampleTimestampMs;
  int _sampleCount = 0;

  double _torsoLengthSum = 0;
  double _shoulderWidthSum = 0;
  double _legLengthSum = 0;
  double _hipYSum = 0;
  double _kneeYSum = 0;

  double get progress => (_validElapsedMs / _requiredMs).clamp(0, 1);
  bool get isComplete => _validElapsedMs >= _requiredMs;

  /// Feeds one processed frame in. Returns false (and does not advance
  /// progress) if the frame isn't usable: a required landmark is missing
  /// or not confidently visible, or the person's measured torso is too
  /// small relative to the frame (standing too far from the camera to
  /// measure reliably) — see AppConfig.minNormalizedTorsoLength.
  bool addSample({
    required Map<PoseLandmarkType, PoseLandmark> landmarks,
    required double frameHeight,
    required int timestampMs,
  }) {
    for (final type in _requiredLandmarks) {
      final landmark = landmarks[type];
      if (landmark == null || landmark.likelihood < AppConfig.minLandmarkVisibility) {
        _lastSampleTimestampMs = null;
        return false;
      }
    }

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder]!;
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder]!;
    final leftHip = landmarks[PoseLandmarkType.leftHip]!;
    final rightHip = landmarks[PoseLandmarkType.rightHip]!;
    final leftKnee = landmarks[PoseLandmarkType.leftKnee]!;
    final rightKnee = landmarks[PoseLandmarkType.rightKnee]!;
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle]!;
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle]!;

    final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;
    final shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2;
    final hipMidX = (leftHip.x + rightHip.x) / 2;
    final hipMidY = (leftHip.y + rightHip.y) / 2;

    final torsoLength = _distanceXY(
      shoulderMidX,
      shoulderMidY,
      hipMidX,
      hipMidY,
    );
    if (torsoLength / frameHeight < AppConfig.minNormalizedTorsoLength) {
      _lastSampleTimestampMs = null;
      return false;
    }

    final shoulderWidth = _distance(leftShoulder, rightShoulder);
    final legLength =
        (_distance(leftHip, leftAnkle) + _distance(rightHip, rightAnkle)) / 2;
    final kneeY = (leftKnee.y + rightKnee.y) / 2;

    final lastTimestamp = _lastSampleTimestampMs;
    if (lastTimestamp != null && timestampMs > lastTimestamp) {
      _validElapsedMs += timestampMs - lastTimestamp;
    }
    _lastSampleTimestampMs = timestampMs;

    _torsoLengthSum += torsoLength;
    _shoulderWidthSum += shoulderWidth;
    _legLengthSum += legLength;
    _hipYSum += hipMidY;
    _kneeYSum += kneeY;
    _sampleCount++;

    return true;
  }

  CalibrationReference? build() {
    if (!isComplete || _sampleCount == 0) return null;
    return CalibrationReference(
      torsoLength: _torsoLengthSum / _sampleCount,
      shoulderWidth: _shoulderWidthSum / _sampleCount,
      legLength: _legLengthSum / _sampleCount,
      standingHipY: _hipYSum / _sampleCount,
      restingKneeY: _kneeYSum / _sampleCount,
    );
  }
}
