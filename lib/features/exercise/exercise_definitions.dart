import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/config.dart';
import 'calibration.dart';

export '../../data/models/exercise_type.dart';

bool _visible(PoseLandmark? landmark) =>
    landmark != null && landmark.likelihood >= AppConfig.minLandmarkVisibility;

double _distance(PoseLandmark a, PoseLandmark b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return sqrt(dx * dx + dy * dy);
}

/// Hip drop relative to the calibrated standing hip position, normalized to
/// leg length. Positive and growing as the user squats down; ~0 standing.
/// Front-facing by design — only needs hips, never a side view.
double? squatMetric(
  Map<PoseLandmarkType, PoseLandmark> landmarks,
  CalibrationReference calibration,
) {
  final leftHip = landmarks[PoseLandmarkType.leftHip];
  final rightHip = landmarks[PoseLandmarkType.rightHip];
  if (!_visible(leftHip) || !_visible(rightHip)) return null;
  final hipY = (leftHip!.y + rightHip!.y) / 2;
  return (hipY - calibration.standingHipY) / calibration.legLength;
}

/// Ankle spread relative to shoulder width. Positive and growing as the
/// feet spread apart. One of jumping jack's two independently-tracked
/// sub-metrics — see exercise_session.dart for how they combine.
double? jumpingJackAnkleMetric(
  Map<PoseLandmarkType, PoseLandmark> landmarks,
  CalibrationReference calibration,
) {
  final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
  final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];
  if (!_visible(leftAnkle) || !_visible(rightAnkle)) return null;
  return _distance(leftAnkle!, rightAnkle!) / calibration.shoulderWidth;
}

/// Wrist height relative to the shoulder line, normalized to torso length.
/// Positive and growing as the arms raise above the shoulders. Jumping
/// jack's other sub-metric.
double? jumpingJackWristMetric(
  Map<PoseLandmarkType, PoseLandmark> landmarks,
  CalibrationReference calibration,
) {
  final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
  final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
  final leftWrist = landmarks[PoseLandmarkType.leftWrist];
  final rightWrist = landmarks[PoseLandmarkType.rightWrist];
  if (!_visible(leftShoulder) ||
      !_visible(rightShoulder) ||
      !_visible(leftWrist) ||
      !_visible(rightWrist)) {
    return null;
  }
  final shoulderY = (leftShoulder!.y + rightShoulder!.y) / 2;
  final wristY = (leftWrist!.y + rightWrist!.y) / 2;
  return (shoulderY - wristY) / calibration.torsoLength;
}

/// Per-leg knee height relative to its calibrated resting position,
/// normalized to leg length. Positive and growing as the knee lifts. Called
/// once per leg by the per-leg state machines in exercise_session.dart.
double? highKneeMetric(
  PoseLandmark? knee,
  CalibrationReference calibration,
) {
  if (!_visible(knee)) return null;
  return (calibration.restingKneeY - knee!.y) / calibration.legLength;
}

/// Wrist height relative to the nose line, normalized to torso length.
/// Only grows positive once the arms clear head height — a true overhead
/// extension, not just a shoulder-height raise.
double? overheadReachMetric(
  Map<PoseLandmarkType, PoseLandmark> landmarks,
  CalibrationReference calibration,
) {
  final nose = landmarks[PoseLandmarkType.nose];
  final leftWrist = landmarks[PoseLandmarkType.leftWrist];
  final rightWrist = landmarks[PoseLandmarkType.rightWrist];
  if (!_visible(nose) || !_visible(leftWrist) || !_visible(rightWrist)) {
    return null;
  }
  final wristY = (leftWrist!.y + rightWrist!.y) / 2;
  return (nose!.y - wristY) / calibration.torsoLength;
}
