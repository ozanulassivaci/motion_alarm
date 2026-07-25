import 'package:flutter/material.dart';

import '../features/alarm/alarm_ring_screen.dart';
import '../features/home/home_screen.dart';
import 'theme/night_theme.dart';

/// Lets AlarmSchedulingService push AlarmRingScreen from its notification
/// response callback, which fires outside any widget's BuildContext.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class MotionAlarmApp extends StatelessWidget {
  const MotionAlarmApp({super.key, this.launchedFromAlarmId});

  /// Set when the app was cold-started by tapping/full-screen-intenting the
  /// alarm notification, so the very first frame is the ring screen instead
  /// of home.
  final String? launchedFromAlarmId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motion Alarm',
      navigatorKey: rootNavigatorKey,
      theme: nightTheme,
      home: launchedFromAlarmId == null
          ? const HomeScreen()
          : AlarmRingScreen(alarmId: launchedFromAlarmId),
    );
  }
}
