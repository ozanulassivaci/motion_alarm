import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/alarm.dart';

const _alarmChannelId = 'alarm_channel';
const _alarmChannelName = 'Alarms';
const _alarmChannelDescription =
    'Full-screen alarm notifications that ring until dismissed.';

/// Wraps flutter_local_notifications for the one thing this app needs from
/// it: scheduling exact, full-screen alarms and cancelling them again.
class AlarmSchedulingService {
  AlarmSchedulingService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> init({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    tz_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.identifier));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: _alarmChannelDescription,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm'),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }

  /// Must be called at alarm-creation time (the night before), not when an
  /// alarm fires. Safe to call repeatedly: each request is a no-op once
  /// already granted.
  Future<bool> requestPermissions() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return true;

    final notificationsGranted =
        await androidPlugin.requestNotificationsPermission() ?? false;
    final exactAlarmsGranted =
        await androidPlugin.requestExactAlarmsPermission() ?? false;
    final fullScreenIntentGranted =
        await androidPlugin.requestFullScreenIntentPermission() ?? false;

    return notificationsGranted &&
        exactAlarmsGranted &&
        fullScreenIntentGranted;
  }

  Future<void> scheduleAlarm(Alarm alarm) async {
    await cancelAlarm(alarm.id);
    if (!alarm.enabled) return;

    if (alarm.repeatDays.isEmpty) {
      await _scheduleOccurrence(
        id: _idFor(alarm.id, 0),
        fireDate: _nextOneTimeOccurrence(alarm),
        matchDateTimeComponents: null,
        payload: alarm.id,
      );
      return;
    }

    for (final weekday in alarm.repeatDays) {
      await _scheduleOccurrence(
        id: _idFor(alarm.id, weekday),
        fireDate: _nextWeekdayOccurrence(alarm, weekday),
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: alarm.id,
      );
    }
  }

  Future<void> cancelAlarm(String alarmId) async {
    for (var weekday = 0; weekday <= 7; weekday++) {
      await _plugin.cancel(id: _idFor(alarmId, weekday));
    }
  }

  Future<void> _scheduleOccurrence({
    required int id,
    required tz.TZDateTime fireDate,
    required DateTimeComponents? matchDateTimeComponents,
    required String payload,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: 'Motion Alarm',
      body: 'Alarmı durdurmak için egzersizi tamamla.',
      scheduledDate: fireDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _alarmChannelId,
          _alarmChannelName,
          channelDescription: _alarmChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm'),
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          visibility: NotificationVisibility.public,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: matchDateTimeComponents,
      payload: payload,
    );
  }

  tz.TZDateTime _nextOneTimeOccurrence(Alarm alarm) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      alarm.hour,
      alarm.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextWeekdayOccurrence(Alarm alarm, int weekday) {
    var scheduled = _nextOneTimeOccurrence(alarm);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// weekday 0 means "one-time"; 1-7 are DateTime.monday..sunday. Combining
  /// with the alarm's own id keeps each alarm's up-to-8 occurrences from
  /// colliding with each other or (short of an unlucky hash collision) with
  /// other alarms.
  int _idFor(String alarmId, int weekday) {
    final base = alarmId.hashCode.abs() % 100000000;
    return base * 10 + weekday;
  }
}
