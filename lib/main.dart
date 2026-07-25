import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/alarm/alarm_list_controller.dart';
import 'features/alarm/alarm_ring_screen.dart';
import 'features/alarm/alarm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  final schedulingService = AlarmSchedulingService(notificationsPlugin);
  await schedulingService.init(
    // Fires when the app is already running (warm) and the user taps the
    // alarm notification or its full-screen intent triggers; cold starts
    // are instead handled below via getNotificationAppLaunchDetails.
    onDidReceiveNotificationResponse: (details) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmRingScreen(alarmId: details.payload),
        ),
      );
    },
  );

  final launchDetails = await notificationsPlugin
      .getNotificationAppLaunchDetails();
  final launchedFromAlarmId = (launchDetails?.didNotificationLaunchApp ?? false)
      ? launchDetails?.notificationResponse?.payload
      : null;

  runApp(
    ProviderScope(
      overrides: [
        alarmSchedulingServiceProvider.overrideWithValue(schedulingService),
      ],
      child: MotionAlarmApp(launchedFromAlarmId: launchedFromAlarmId),
    ),
  );
}
