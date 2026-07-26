import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _tag = '[NativeAlarmRingBridge]';

/// Bridges to AlarmRingService, the native foreground service that owns
/// alarm sound + vibration independently of any Activity — see CLAUDE.md's
/// "Alarm ownership" architecture. This class only sends commands and reads
/// launch state; the service itself is the source of truth for whether the
/// alarm is currently ringing, and its lifecycle is never driven from here.
class NativeAlarmRingBridge {
  static const _channel = MethodChannel('motion_alarm/ring_service');

  /// Must be called exactly once, at startup before `runApp` (mirroring
  /// AlarmSchedulingService.init()'s onDidReceiveNotificationResponse) —
  /// registers the *warm* path: the Activity/engine was already alive and
  /// the user tapped the service-owned notification, so MainActivity pushes
  /// straight to Dart via onNewIntent rather than through a cold start.
  void init({required void Function(String alarmId) onAlarmNotificationTapped}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAlarmNotificationTapped') {
        final alarmId = call.arguments as String?;
        debugPrint('$_tag onAlarmNotificationTapped: alarmId=$alarmId');
        if (alarmId != null) onAlarmNotificationTapped(alarmId);
      }
      return null;
    });
  }

  /// The *cold* counterpart to [init]'s warm path: reads (and clears) the
  /// alarmId this process was launched with, if it was launched by tapping
  /// AlarmRingService's own notification rather than
  /// flutter_local_notifications' (which is already covered by
  /// getNotificationAppLaunchDetails()). Call once at startup.
  Future<String?> consumeLaunchAlarmId() async {
    try {
      return await _channel.invokeMethod<String>('consumeLaunchAlarmId');
    } catch (error) {
      debugPrint('$_tag consumeLaunchAlarmId FAILED: $error');
      return null;
    }
  }

  /// Schedules a native AlarmManager entry, in parallel with whatever
  /// flutter_local_notifications already scheduled for the same [id] and
  /// instant, that starts AlarmRingService directly — independent of the
  /// Flutter engine, since full-screen intent doesn't force-launch the
  /// Activity when the device is unlocked (see CLAUDE.md).
  Future<void> scheduleRing({
    required int id,
    required DateTime triggerAt,
    required String alarmId,
    required bool exact,
  }) async {
    try {
      await _channel.invokeMethod('scheduleRing', {
        'id': id,
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
        'alarmId': alarmId,
        'exact': exact,
      });
    } catch (error) {
      debugPrint('$_tag scheduleRing($id) FAILED: $error');
    }
  }

  Future<void> cancelRing(int id) async {
    try {
      await _channel.invokeMethod('cancelRing', {'id': id});
    } catch (error) {
      debugPrint('$_tag cancelRing($id) FAILED: $error');
    }
  }

  /// Called when "Egzersize Başla" is tapped: lowers the ringing alarm's
  /// volume instead of stopping it, per CLAUDE.md's volume rule — the alarm
  /// keeps nagging (quietly) through the whole workout so dismissing it
  /// isn't a free snooze. Also stops the alarm's own vibration loop, so the
  /// single vibration motor is free for per-rep haptic feedback.
  Future<void> lowerVolume({double fraction = 0.15}) async {
    try {
      await _channel.invokeMethod('lowerVolume', {'fraction': fraction});
    } catch (error) {
      debugPrint('$_tag lowerVolume FAILED: $error');
    }
  }

  /// Fully stops the ring: called only on workout completion or a
  /// confirmed emergency exit.
  Future<void> stopRinging() async {
    try {
      await _channel.invokeMethod('stopRinging');
    } catch (error) {
      debugPrint('$_tag stopRinging FAILED: $error');
    }
  }
}
