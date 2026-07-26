import 'package:flutter/material.dart';

import '../../data/models/exercise_type.dart';

/// Normalized (0..1 on both axes) joint positions for a simple stick
/// figure — analogous to the real ML Kit landmarks PosePainter draws, but
/// computed by a parametric function of a looping animation phase instead
/// of camera detection.
enum _Joint {
  head,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftHand,
  rightHand,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftFoot,
  rightFoot,
}

typedef _Pose = Map<_Joint, Offset>;

const _bones = [
  [_Joint.leftShoulder, _Joint.rightShoulder],
  [_Joint.leftShoulder, _Joint.leftElbow],
  [_Joint.leftElbow, _Joint.leftHand],
  [_Joint.rightShoulder, _Joint.rightElbow],
  [_Joint.rightElbow, _Joint.rightHand],
  [_Joint.leftShoulder, _Joint.leftHip],
  [_Joint.rightShoulder, _Joint.rightHip],
  [_Joint.leftHip, _Joint.rightHip],
  [_Joint.leftHip, _Joint.leftKnee],
  [_Joint.leftKnee, _Joint.leftFoot],
  [_Joint.rightHip, _Joint.rightKnee],
  [_Joint.rightKnee, _Joint.rightFoot],
];

/// 0 -> 1 -> 0 across one loop — the same triangle-wave technique
/// WorkoutScreen's completion-flash animation already uses.
double _triangleWave(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;

_Pose _basePose({
  double hipDrop = 0,
  double kneeBow = 0,
  double legSpread = 0,
  double leftArmRaise = 0,
  double rightArmRaise = 0,
  double leftKneeLift = 0,
  double rightKneeLift = 0,
}) {
  const centerX = 0.5;
  const headY = 0.12;
  const shoulderY = 0.24;
  const hipHalfWidth = 0.09;
  const shoulderHalfWidth = 0.14;
  const feetY = 0.92;
  const armLength = 0.22;

  final hipY = 0.55 + hipDrop * 0.12;
  final leftHip = Offset(centerX - hipHalfWidth, hipY);
  final rightHip = Offset(centerX + hipHalfWidth, hipY);

  final leftFoot = Offset(
    centerX - hipHalfWidth * 1.3 - legSpread * 0.18,
    feetY - leftKneeLift * 0.12,
  );
  final rightFoot = Offset(
    centerX + hipHalfWidth * 1.3 + legSpread * 0.18,
    feetY - rightKneeLift * 0.12,
  );
  final leftKnee = Offset(
    (leftHip.dx + leftFoot.dx) / 2 - kneeBow * 0.06 - leftKneeLift * 0.05,
    (leftHip.dy + leftFoot.dy) / 2 - leftKneeLift * 0.1,
  );
  final rightKnee = Offset(
    (rightHip.dx + rightFoot.dx) / 2 + kneeBow * 0.06 + rightKneeLift * 0.05,
    (rightHip.dy + rightFoot.dy) / 2 - rightKneeLift * 0.1,
  );

  final leftShoulder = Offset(centerX - shoulderHalfWidth, shoulderY);
  final rightShoulder = Offset(centerX + shoulderHalfWidth, shoulderY);
  // armRaise: 0 = hanging at the side, 1 = fully overhead.
  final leftHand = Offset.lerp(
    Offset(leftShoulder.dx - 0.02, leftShoulder.dy + armLength),
    Offset(leftShoulder.dx - 0.10, leftShoulder.dy - armLength),
    leftArmRaise,
  )!;
  final rightHand = Offset.lerp(
    Offset(rightShoulder.dx + 0.02, rightShoulder.dy + armLength),
    Offset(rightShoulder.dx + 0.10, rightShoulder.dy - armLength),
    rightArmRaise,
  )!;
  final leftElbow = Offset.lerp(leftShoulder, leftHand, 0.55)!;
  final rightElbow = Offset.lerp(rightShoulder, rightHand, 0.55)!;

  return {
    _Joint.head: const Offset(centerX, headY),
    _Joint.leftShoulder: leftShoulder,
    _Joint.rightShoulder: rightShoulder,
    _Joint.leftElbow: leftElbow,
    _Joint.rightElbow: rightElbow,
    _Joint.leftHand: leftHand,
    _Joint.rightHand: rightHand,
    _Joint.leftHip: leftHip,
    _Joint.rightHip: rightHip,
    _Joint.leftKnee: leftKnee,
    _Joint.rightKnee: rightKnee,
    _Joint.leftFoot: leftFoot,
    _Joint.rightFoot: rightFoot,
  };
}

// Each function is a pure `t (0..1 loop) -> pose` mapping — the same
// exercise-agnostic-engine-plus-per-exercise-pure-function shape
// exercise_definitions.dart already uses for the real detection metrics.

_Pose _squatPose(double t) {
  final wave = _triangleWave(t);
  return _basePose(hipDrop: wave, kneeBow: wave);
}

_Pose _jumpingJackPose(double t) {
  // One shared wave drives legs spreading AND arms raising in sync —
  // mirrors the two AND-ed sub-metrics jumping jacks are actually detected
  // by (see jumpingJackAnkleMetric/jumpingJackWristMetric).
  final wave = _triangleWave(t);
  return _basePose(legSpread: wave, leftArmRaise: wave, rightArmRaise: wave);
}

_Pose _highKneesPose(double t) {
  // Two waves 180° out of phase — one per leg — so knees lift alternately.
  final leftWave = _triangleWave(t);
  final rightWave = _triangleWave((t + 0.5) % 1.0);
  return _basePose(leftKneeLift: leftWave, rightKneeLift: rightWave);
}

_Pose _overheadReachPose(double t) {
  final wave = _triangleWave(t);
  return _basePose(leftArmRaise: wave, rightArmRaise: wave);
}

_Pose _poseFor(ExerciseType type, double t) => switch (type) {
  ExerciseType.squat => _squatPose(t),
  ExerciseType.jumpingJack => _jumpingJackPose(t),
  ExerciseType.highKnees => _highKneesPose(t),
  ExerciseType.overheadReach => _overheadReachPose(t),
};

/// Draws a procedural stick-figure demo of one exercise's motion — the same
/// dot-and-line joint styling as the real skeleton overlay in
/// pose_painter.dart, computed from a parametric pose function instead of
/// camera detection. Same "no image asset, CustomPainter" technique
/// GhostSilhouettePainter already uses, extended to move over time — zero
/// assets, zero licensing risk.
class ExerciseDemoPainter extends CustomPainter {
  ExerciseDemoPainter({
    required this.type,
    required this.t,
    required this.color,
  });

  final ExerciseType type;

  /// 0..1, one full loop of the exercise's motion.
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.035
      ..strokeCap = StrokeCap.round
      ..color = color;
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final pose = _poseFor(type, t);
    Offset point(_Joint joint) {
      final normalized = pose[joint]!;
      return Offset(normalized.dx * size.width, normalized.dy * size.height);
    }

    for (final bone in _bones) {
      canvas.drawLine(point(bone[0]), point(bone[1]), linePaint);
    }
    canvas.drawCircle(point(_Joint.head), size.shortestSide * 0.09, dotPaint);
    for (final joint in _Joint.values) {
      if (joint == _Joint.head) continue;
      canvas.drawCircle(point(joint), size.shortestSide * 0.025, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ExerciseDemoPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.t != t ||
        oldDelegate.color != color;
  }
}
