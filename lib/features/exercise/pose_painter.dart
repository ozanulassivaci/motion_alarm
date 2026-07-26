import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/config.dart';

const _accentColor = Color(0xFF2FE6C4);

const _connections = [
  [PoseLandmarkType.leftEar, PoseLandmarkType.leftEye],
  [PoseLandmarkType.leftEye, PoseLandmarkType.nose],
  [PoseLandmarkType.nose, PoseLandmarkType.rightEye],
  [PoseLandmarkType.rightEye, PoseLandmarkType.rightEar],
  [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
  [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
  [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
  [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
  [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
  [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
  [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
  [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
  [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
  [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
  [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
  [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],
  [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex],
  [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
  [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
  [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
  [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex],
];

/// Draws the detected skeleton on top of the camera preview. The coordinate
/// mapping (translateX/translateY) matches google_ml_kit_flutter's own
/// reference example verbatim — this is the usual source of misaligned
/// skeletons, so it is not reinvented here.
class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  // Stage 1 profiling (kDebugMode only): total time spent inside paint(),
  // read and reset once per second by PosePipelineController. Static
  // because a new PosePainter is constructed on every rebuild.
  static double _totalPaintMs = 0;
  static int _paintCount = 0;

  static double get averagePaintMs =>
      _paintCount == 0 ? 0 : _totalPaintMs / _paintCount;

  static void resetPaintStats() {
    _totalPaintMs = 0;
    _paintCount = 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    _paint(canvas, size);
    if (stopwatch != null) {
      _totalPaintMs += stopwatch.elapsedMicroseconds / 1000;
      _paintCount++;
    }
  }

  void _paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = _accentColor;
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _accentColor;

    for (final pose in poses) {
      for (final connection in _connections) {
        final a = pose.landmarks[connection[0]];
        final b = pose.landmarks[connection[1]];
        if (a == null || b == null) continue;
        if (a.likelihood < AppConfig.minLandmarkVisibility ||
            b.likelihood < AppConfig.minLandmarkVisibility) {
          continue;
        }
        canvas.drawLine(
          Offset(_translateX(a.x, size), _translateY(a.y, size)),
          Offset(_translateX(b.x, size), _translateY(b.y, size)),
          linePaint,
        );
      }
      for (final landmark in pose.landmarks.values) {
        if (landmark.likelihood < AppConfig.minLandmarkVisibility) continue;
        canvas.drawCircle(
          Offset(_translateX(landmark.x, size), _translateY(landmark.y, size)),
          4,
          dotPaint,
        );
      }
    }
  }

  double _translateX(double x, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x *
            canvasSize.width /
            (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation270deg:
        return canvasSize.width -
            x *
                canvasSize.width /
                (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        switch (cameraLensDirection) {
          case CameraLensDirection.back:
            return x * canvasSize.width / imageSize.width;
          default:
            return canvasSize.width - x * canvasSize.width / imageSize.width;
        }
    }
  }

  double _translateY(double y, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y *
            canvasSize.height /
            (Platform.isIOS ? imageSize.height : imageSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / imageSize.height;
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    // The pipeline notifies listeners once per second even when only fps
    // changed (no new pose data) — skip the actual canvas work in that
    // case. `poses` is only reassigned when a new detection completes, so
    // identity comparison cheaply detects "nothing new happened".
    return !identical(oldDelegate.poses, poses) ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation;
  }
}
