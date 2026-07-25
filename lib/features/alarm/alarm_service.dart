import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/alarm.dart';

const _alarmChannelId = 'alarm_channel';
const _alarmChannelName = 'Alarms';
const _alarmChannelDescription =
    'Full-screen alarm notifications that ring until dismissed.';

/// Prefix every log line so `adb logcat` / `flutter logs` output can be
/// grepped for exactly this service: `adb logcat | grep AlarmSchedulingService`.
const _tag = '[AlarmSchedulingService]';

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
    debugPrint('$_tag init: local timezone set to ${tz.local.name}');

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
    debugPrint('$_tag init: plugin.initialize returned $initialized');

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
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
      debugPrint('$_tag init: notification channel "$_alarmChannelId" created');
    } catch (error, stackTrace) {
      debugPrint('$_tag init: FAILED to create notification channel: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Must be called at alarm-creation time (the night before), not when an
  /// alarm fires. Safe to call repeatedly: each request is a no-op once
  /// already granted. Also called internally by [scheduleAlarm], so this is
  /// mainly useful for showing the user an explicit result right after they
  /// save an alarm.
  Future<bool> requestPermissions() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      debugPrint('$_tag requestPermissions: no Android plugin (not on Android)');
      return true;
    }

    Future<bool> requestAsync(String name, Future<bool?> Function() call) async {
      try {
        final granted = await call() ?? false;
        debugPrint('$_tag requestPermissions: $name granted=$granted');
        return granted;
      } catch (error, stackTrace) {
        debugPrint('$_tag requestPermissions: $name FAILED: $error');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }
    }

    final notificationsGranted = await requestAsync(
      'notifications',
      androidPlugin.requestNotificationsPermission,
    );
    final exactAlarmsGranted = await requestAsync(
      'exactAlarms',
      androidPlugin.requestExactAlarmsPermission,
    );
    final fullScreenIntentGranted = await requestAsync(
      'fullScreenIntent',
      androidPlugin.requestFullScreenIntentPermission,
    );

    return notificationsGranted &&
        exactAlarmsGranted &&
        fullScreenIntentGranted;
  }

  Future<void> scheduleAlarm(Alarm alarm) async {
    debugPrint(
      '$_tag scheduleAlarm(${alarm.id}): enabled=${alarm.enabled} '
      'time=${alarm.hour}:${alarm.minute} repeatDays=${alarm.repeatDays}',
    );
    await cancelAlarm(alarm.id);
    if (!alarm.enabled) {
      debugPrint('$_tag scheduleAlarm(${alarm.id}): disabled, not scheduling');
      return;
    }

    // Ask now (deep-links to the system "Alarms & reminders" / full-screen
    // intent settings screens if needed) so creating an alarm is what
    // triggers the prompts, per CLAUDE.md ("night before", not at fire time).
    await requestPermissions();

    final scheduleMode = await _resolveScheduleMode();

    if (alarm.repeatDays.isEmpty) {
      await _scheduleOccurrence(
        id: _idFor(alarm.id, 0),
        fireDate: _nextOneTimeOccurrence(alarm),
        matchDateTimeComponents: null,
        payload: alarm.id,
        scheduleMode: scheduleMode,
      );
      return;
    }

    for (final weekday in alarm.repeatDays) {
      await _scheduleOccurrence(
        id: _idFor(alarm.id, weekday),
        fireDate: _nextWeekdayOccurrence(alarm, weekday),
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: alarm.id,
        scheduleMode: scheduleMode,
      );
    }
  }

  /// Debug-only: schedules straight through the same permission/channel/
  /// zonedSchedule path as a real alarm, but at a fixed short delay instead
  /// of an hour:minute — for quickly reproducing the firing/delivery path
  /// without waiting on the clock or the time picker. Uses a reserved id
  /// outside the range `_idFor` can ever produce, so it can never collide
  /// with a real alarm's scheduled occurrences.
  static const testAlarmId = 999999999;
  static const testAlarmPayload = '__test_alarm__';

  Future<void> scheduleTestAlarm({
    Duration delay = const Duration(seconds: 10),
  }) async {
    debugPrint('$_tag scheduleTestAlarm: firing in ${delay.inSeconds}s');
    await requestPermissions();
    final scheduleMode = await _resolveScheduleMode();
    await _scheduleOccurrence(
      id: testAlarmId,
      fireDate: tz.TZDateTime.now(tz.local).add(delay),
      matchDateTimeComponents: null,
      payload: testAlarmPayload,
      scheduleMode: scheduleMode,
    );
  }

  /// Exact scheduling throws a platform exception if the exact-alarm
  /// permission isn't currently granted (checked live, independently of
  /// whatever [requestPermissions] returned — the user may have granted it
  /// manually in system Settings outside our own prompt). Falling back to
  /// inexact rather than throwing means the alarm still gets scheduled, just
  /// with looser timing, instead of silently scheduling nothing at all.
  Future<AndroidScheduleMode> _resolveScheduleMode() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final canScheduleExact =
        await androidPlugin?.canScheduleExactNotifications() ?? false;
    debugPrint('$_tag canScheduleExactNotifications=$canScheduleExact');
    if (!canScheduleExact) {
      debugPrint(
        '$_tag WARNING: exact-alarm permission not granted; falling back to '
        'inexactAllowWhileIdle. Firing time may drift. Grant "Alarms & '
        'reminders" for this app in system Settings for reliable timing.',
      );
    }
    return canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> cancelAlarm(String alarmId) async {
    for (var weekday = 0; weekday <= 7; weekday++) {
      await _plugin.cancel(id: _idFor(alarmId, weekday));
    }
    debugPrint('$_tag cancelAlarm($alarmId): cancelled ids for weekdays 0-7');
  }

  Future<void> _scheduleOccurrence({
    required int id,
    required tz.TZDateTime fireDate,
    required DateTimeComponents? matchDateTimeComponents,
    required String payload,
    required AndroidScheduleMode scheduleMode,
  }) async {
    debugPrint(
      '$_tag scheduleAlarm: occurrence id=$id fireDate=$fireDate '
      '(tz=${fireDate.location.name}) mode=$scheduleMode '
      'repeat=$matchDateTimeComponents',
    );
    try {
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
        androidScheduleMode: scheduleMode,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
      debugPrint('$_tag scheduleAlarm: occurrence id=$id scheduled OK');
    } catch (error, stackTrace) {
      debugPrint('$_tag scheduleAlarm: occurrence id=$id FAILED: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
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
