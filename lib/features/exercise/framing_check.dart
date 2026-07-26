import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/config.dart';

enum FramingStatus {
  /// No pose detected at all — likely too dark, or no one in frame.
  noPersonDetected,

  /// A pose was detected but not all required landmarks are confidently
  /// visible — likely partially out of frame.
  incompleteFraming,

  /// All required landmarks are present and confidently visible.
  ready,
}

class FramingCheckResult {
  const FramingCheckResult({
    required this.status,
    required this.missingLandmarks,
  });

  final FramingStatus status;
  final List<PoseLandmarkType> missingLandmarks;

  /// Turkish status line per CLAUDE.md's single framing standard.
  String get message => switch (status) {
    FramingStatus.noPersonDetected => 'Işığı aç, seni göremiyorum',
    FramingStatus.incompleteFraming => 'Tüm vücudun görünmüyor',
    FramingStatus.ready => 'Hazır',
  };
}

/// Pure function: given the poses detected in one frame, reports whether the
/// required landmarks (core/config.dart) are present and confidently visible.
///
/// Runs once per processed frame, so it's written to allocate nothing in the
/// common case: a cheap boolean scan first, only building the missing-list
/// when framing actually turns out to be incomplete.
FramingCheckResult checkFraming(List<Pose> poses) {
  if (poses.isEmpty) {
    return const FramingCheckResult(
      status: FramingStatus.noPersonDetected,
      missingLandmarks: [],
    );
  }

  final pose = poses.first;
  var hasMissing = false;
  for (final type in AppConfig.requiredFramingLandmarks) {
    if ((pose.landmarks[type]?.likelihood ?? 0) < AppConfig.minLandmarkVisibility) {
      hasMissing = true;
      break;
    }
  }

  if (!hasMissing) {
    return const FramingCheckResult(status: FramingStatus.ready, missingLandmarks: []);
  }

  final missing = <PoseLandmarkType>[
    for (final type in AppConfig.requiredFramingLandmarks)
      if ((pose.landmarks[type]?.likelihood ?? 0) < AppConfig.minLandmarkVisibility)
        type,
  ];
  return FramingCheckResult(
    status: FramingStatus.incompleteFraming,
    missingLandmarks: missing,
  );
}
