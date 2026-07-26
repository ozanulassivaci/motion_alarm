package com.example.motion_alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges to [AlarmRingService]: schedules/cancels the native, parallel
 * AlarmManager entry that starts it (see AlarmRingReceiver for why this is
 * separate from flutter_local_notifications' own scheduling), relays
 * lowerVolume/stopRinging commands to it, and surfaces the alarmId this
 * Activity was (re)launched with — either from a cold start (read once via
 * `consumeLaunchAlarmId`) or, if the Activity/engine was already alive, by
 * pushing `onAlarmNotificationTapped` straight to Dart from [onNewIntent].
 */
class MainActivity : FlutterActivity() {
    companion object {
        const val ALARM_ID_EXTRA = "alarmId"
        private const val CHANNEL_NAME = "motion_alarm/ring_service"
    }

    private var methodChannel: MethodChannel? = null
    private var pendingLaunchAlarmId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingLaunchAlarmId = intent?.getStringExtra(ALARM_ID_EXTRA)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleRing" -> {
                    val id = call.argument<Int>("id")!!
                    val triggerAtMillis = (call.argument<Number>("triggerAtMillis")!!).toLong()
                    val alarmId = call.argument<String>("alarmId")
                    val exact = call.argument<Boolean>("exact") ?: false
                    scheduleRing(id, triggerAtMillis, alarmId, exact)
                    result.success(null)
                }
                "cancelRing" -> {
                    val id = call.argument<Int>("id")!!
                    cancelRing(id)
                    result.success(null)
                }
                "setExerciseActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    val fraction = (call.argument<Number>("fraction") ?: 0.15).toFloat()
                    AlarmRingService.setExerciseActive(active, fraction)
                    result.success(null)
                }
                "stopRinging" -> {
                    AlarmRingService.stopRinging(applicationContext)
                    result.success(null)
                }
                "consumeLaunchAlarmId" -> {
                    result.success(pendingLaunchAlarmId)
                    pendingLaunchAlarmId = null
                }
                "isRinging" -> {
                    result.success(
                        mapOf(
                            "ringing" to AlarmRingService.isRinging(),
                            "alarmId" to AlarmRingService.currentAlarmId(),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val alarmId = intent.getStringExtra(ALARM_ID_EXTRA) ?: return
        // The engine/Activity was already alive (e.g. the app was open in
        // the background) — a cold-start `consumeLaunchAlarmId` read would
        // never happen, so push straight to Dart instead.
        methodChannel?.invokeMethod("onAlarmNotificationTapped", alarmId)
    }

    private fun ringPendingIntent(id: Int, alarmId: String?): PendingIntent {
        val ringIntent = Intent(this, AlarmRingReceiver::class.java).apply {
            if (alarmId != null) putExtra(AlarmRingService.EXTRA_ALARM_ID, alarmId)
            // Reused as this notification's id so AlarmRingService's own
            // post supersedes flutter_local_notifications' one instead of
            // showing as a second, duplicate notification (both share the
            // "alarm_channel" channel id already).
            putExtra(AlarmRingService.EXTRA_NOTIFICATION_ID, id)
        }
        return PendingIntent.getBroadcast(
            this,
            id,
            ringIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun scheduleRing(id: Int, triggerAtMillis: Long, alarmId: String?, exact: Boolean) {
        val alarmManager = ContextCompat.getSystemService(this, AlarmManager::class.java) ?: return
        val pendingIntent = ringPendingIntent(id, alarmId)
        if (exact) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    private fun cancelRing(id: Int) {
        val alarmManager = ContextCompat.getSystemService(this, AlarmManager::class.java) ?: return
        // PendingIntent matching ignores extras, so alarmId doesn't matter here.
        alarmManager.cancel(ringPendingIntent(id, null))
    }
}
