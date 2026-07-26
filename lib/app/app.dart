import 'package:flutter/material.dart';

import '../features/alarm/alarm_ring_screen.dart';
import '../features/alarm/native_alarm_ring_bridge.dart';
import '../features/home/home_screen.dart';
import 'theme/night_theme.dart';

const _tag = '[MotionAlarmApp]';

/// Lets AlarmSchedulingService push AlarmRingScreen from its notification
/// response callback, which fires outside any widget's BuildContext.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// True for as long as AlarmRingScreen or WorkoutScreen is the active
/// screen — set in AlarmRingScreen.initState, cleared only by
/// WorkoutScreen's shared _exitToHome path (the two screens replace each
/// other via pushReplacement, so this must span both rather than being
/// cleared/set independently by each). Lets the resume check below tell
/// "already showing the alarm flow" apart from "showing something else
/// while the alarm rings in the background".
bool isAlarmFlowActive = false;

class MotionAlarmApp extends StatefulWidget {
  const MotionAlarmApp({super.key, this.launchedFromAlarmId});

  /// Set when the app was cold-started by tapping/full-screen-intenting the
  /// alarm notification, so the very first frame is the ring screen instead
  /// of home.
  final String? launchedFromAlarmId;

  @override
  State<MotionAlarmApp> createState() => _MotionAlarmAppState();
}

class _MotionAlarmAppState extends State<MotionAlarmApp> with WidgetsBindingObserver {
  final _ringBridge = NativeAlarmRingBridge();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkIfAlarmNeedsToBeShown();
  }

  /// Covers the case flutter_local_notifications' own tap-detection and
  /// AlarmRingService's notification/onNewIntent path both miss: the app
  /// process was already alive showing something other than the alarm flow
  /// (e.g. HomeScreen, opened before the alarm fired) and is simply resumed
  /// from the background — by the launcher icon, Recents, anything — with
  /// no new Intent at all. Launching/reopening the app must never appear to
  /// be a way past a still-ringing alarm.
  Future<void> _checkIfAlarmNeedsToBeShown() async {
    if (isAlarmFlowActive) return;
    final status = await _ringBridge.isRinging();
    if (!status.ringing) return;
    debugPrint('$_tag resumed while still ringing; routing to AlarmRingScreen');
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AlarmRingScreen(alarmId: status.alarmId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motion Alarm',
      navigatorKey: rootNavigatorKey,
      theme: nightTheme,
      home: widget.launchedFromAlarmId == null
          ? const HomeScreen()
          : AlarmRingScreen(alarmId: widget.launchedFromAlarmId),
    );
  }
}
