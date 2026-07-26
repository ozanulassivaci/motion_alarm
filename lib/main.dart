import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/alarm/alarm_list_controller.dart';
import 'features/alarm/alarm_ring_screen.dart';
import 'features/alarm/alarm_service.dart';
import 'features/alarm/native_alarm_ring_bridge.dart';

const _tag = '[main]';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  final schedulingService = AlarmSchedulingService(notificationsPlugin);
  await schedulingService.init(
    // Fires when the app is already running (warm) and the user taps the
    // alarm notification or its full-screen intent triggers; cold starts
    // are instead handled below via getNotificationAppLaunchDetails.
    onDidReceiveNotificationResponse: (details) {
      debugPrint('$_tag onDidReceiveNotificationResponse: payload=${details.payload}');
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmRingScreen(alarmId: details.payload),
        ),
      );
    },
  );

  final ringBridge = NativeAlarmRingBridge();
  ringBridge.init(
    // The warm-path counterpart of the notification response callback
    // above, but for AlarmRingService's own notification (see
    // NativeAlarmRingBridge) rather than flutter_local_notifications'.
    onAlarmNotificationTapped: (alarmId) {
      debugPrint('$_tag onAlarmNotificationTapped: alarmId=$alarmId');
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => AlarmRingScreen(alarmId: alarmId)),
      );
    },
  );

  final launchDetails = await notificationsPlugin
      .getNotificationAppLaunchDetails();
  var launchedFromAlarmId = (launchDetails?.didNotificationLaunchApp ?? false)
      ? launchDetails?.notificationResponse?.payload
      // Cold-start counterpart: covers being launched by tapping
      // AlarmRingService's own notification instead.
      : await ringBridge.consumeLaunchAlarmId();
  if (launchedFromAlarmId == null) {
    // Neither notification path launched this process — covers being
    // launched from the plain launcher icon while AlarmRingService is
    // still ringing in the background. Launching the app must never appear
    // to be a way past a still-ringing alarm.
    final status = await ringBridge.isRinging();
    if (status.ringing) launchedFromAlarmId = status.alarmId;
  }
  debugPrint(
    '$_tag didNotificationLaunchApp=${launchDetails?.didNotificationLaunchApp ?? false} '
    'launchedFromAlarmId=$launchedFromAlarmId',
  );

  runApp(
    ProviderScope(
      overrides: [
        alarmSchedulingServiceProvider.overrideWithValue(schedulingService),
      ],
      child: MotionAlarmApp(launchedFromAlarmId: launchedFromAlarmId),
    ),
  );
}
