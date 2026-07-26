package com.example.motion_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Fired by a native AlarmManager entry scheduled in parallel with
 * flutter_local_notifications' own (see MainActivity.scheduleRing /
 * NativeAlarmRingBridge on the Dart side). Starting AlarmRingService from a
 * plain BroadcastReceiver — rather than from the Flutter engine — means the
 * ring starts even when the device is unlocked and full-screen intent only
 * shows a heads-up notification without ever launching the Activity.
 */
class AlarmRingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getStringExtra(AlarmRingService.EXTRA_ALARM_ID)
        val serviceIntent = Intent(context, AlarmRingService::class.java).apply {
            if (alarmId != null) putExtra(AlarmRingService.EXTRA_ALARM_ID, alarmId)
        }
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
