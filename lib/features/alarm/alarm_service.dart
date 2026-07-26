import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/config.dart';
import '../../data/models/alarm.dart';
import '../../data/models/exercise_type.dart';
import 'native_alarm_ring_bridge.dart';

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
  AlarmSchedulingService(this._plugin, [NativeAlarmRingBridge? ringBridge])
    : _ringBridge = ringBridge ?? NativeAlarmRingBridge();

  final FlutterLocalNotificationsPlugin _plugin;
  final NativeAlarmRingBridge _ringBridge;

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
  static const _testAlarmPayloadPrefix = '__test_alarm__';

  /// [difficulty]/[exercisePool] let the dev-only test-alarm config sheet
  /// (home_screen.dart) choose what WorkoutScreen draws its workout from,
  /// so Medium/Hard's multi-exercise path is reachable without waiting for
  /// a real alarm. Omitted (a bare short-press fire), the payload carries
  /// no config and WorkoutScreen falls back to Easy + all four exercises,
  /// exactly as before.
  Future<void> scheduleTestAlarm({
    Duration delay = const Duration(seconds: 10),
    AlarmDifficulty? difficulty,
    Set<ExerciseType>? exercisePool,
  }) async {
    final payload = _buildTestAlarmPayload(difficulty, exercisePool);
    debugPrint(
      '$_tag scheduleTestAlarm: firing in ${delay.inSeconds}s '
      'difficulty=${difficulty?.name} '
      'exercisePool=${exercisePool?.map((type) => type.name).join(",")}',
    );
    await requestPermissions();
    final scheduleMode = await _resolveScheduleMode();
    await _scheduleOccurrence(
      id: testAlarmId,
      fireDate: tz.TZDateTime.now(tz.local).add(delay),
      matchDateTimeComponents: null,
      payload: payload,
      scheduleMode: scheduleMode,
    );
  }

  static String _buildTestAlarmPayload(
    AlarmDifficulty? difficulty,
    Set<ExerciseType>? exercisePool,
  ) {
    if (difficulty == null || exercisePool == null || exercisePool.isEmpty) {
      return _testAlarmPayloadPrefix;
    }
    final poolNames = exercisePool.map((type) => type.name).join(',');
    return '$_testAlarmPayloadPrefix|${difficulty.name}|$poolNames';
  }

  /// Parses a payload produced by [scheduleTestAlarm]. Returns null if
  /// [payload] isn't a test-alarm payload at all, or is a bare one with no
  /// dev-picked config — callers should fall back to their own default in
  /// that case, exactly like a real alarm id that matches nothing.
  static ({AlarmDifficulty difficulty, Set<ExerciseType> exercisePool})?
  parseTestAlarmConfig(String? payload) {
    if (payload == null || !payload.startsWith(_testAlarmPayloadPrefix)) {
      return null;
    }
    final parts = payload.split('|');
    if (parts.length != 3) return null;
    try {
      final difficulty = AlarmDifficulty.values.byName(parts[1]);
      final exercisePool = parts[2]
          .split(',')
          .map((name) => ExerciseType.values.byName(name))
          .toSet();
      if (exercisePool.isEmpty) return null;
      return (difficulty: difficulty, exercisePool: exercisePool);
    } catch (error) {
      debugPrint(
        '$_tag parseTestAlarmConfig: FAILED to parse "$payload": $error',
      );
      return null;
    }
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
      final id = _idFor(alarmId, weekday);
      await _plugin.cancel(id: id);
      await _ringBridge.cancelRing(id);
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

    // Parallel native entry that starts AlarmRingService directly, so the
    // alarm rings independently of the Flutter engine ever starting — see
    // NativeAlarmRingBridge for why flutter_local_notifications' own
    // zonedSchedule above can't be extended to do this itself. Offset
    // slightly so AlarmRingService's notification post deterministically
    // supersedes flutter_local_notifications' rather than racing it — see
    // AppConfig.ringServiceStartDelayMs.
    await _ringBridge.scheduleRing(
      id: id,
      triggerAt: fireDate.add(
        const Duration(milliseconds: AppConfig.ringServiceStartDelayMs),
      ),
      alarmId: payload,
      exact: scheduleMode == AndroidScheduleMode.exactAllowWhileIdle,
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
