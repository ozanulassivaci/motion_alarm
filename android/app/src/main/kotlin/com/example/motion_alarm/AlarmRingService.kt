package com.example.motion_alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

/**
 * Owns alarm ringing (looping sound + vibration) independently of any
 * Activity, so backgrounding, swiping it away from Recents, or the back
 * gesture can never silence it — see CLAUDE.md's "Alarm ownership"
 * architecture. The Flutter UI never touches a MediaPlayer/Vibrator again;
 * it only sends `lowerVolume`/`stopRinging` commands through MainActivity's
 * MethodChannel. This service is started by [AlarmRingReceiver], which is
 * fired by a native AlarmManager entry scheduled in parallel with
 * flutter_local_notifications' own — see NativeAlarmRingBridge for why a
 * second, parallel entry is necessary rather than hooking the existing one.
 */
class AlarmRingService : Service() {

    companion object {
        const val EXTRA_ALARM_ID = "alarmId"
        private const val NOTIFICATION_ID = 100001
        private const val CHANNEL_ID = "alarm_channel"

        @Volatile
        private var instance: AlarmRingService? = null

        fun isRinging(): Boolean = instance != null

        fun lowerVolume(fraction: Float) {
            instance?.setVolumeFraction(fraction)
        }

        fun stopRinging(context: Context) {
            val running = instance
            if (running != null) {
                running.stopSelfAndCleanUp()
            } else {
                // Nothing running: still clear a stray notification if one
                // is somehow left over (e.g. a previous process died
                // without reaching onDestroy).
                val manager = context.getSystemService(NotificationManager::class.java)
                manager?.cancel(NOTIFICATION_ID)
            }
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val alarmId = intent?.getStringExtra(EXTRA_ALARM_ID)
        startForegroundWithNotification(alarmId)
        startRinging()
        // START_STICKY: if the system kills this process under memory
        // pressure, it restarts the service (with a null intent). Silently
        // losing the alarm would be worse than it restarting the ring from
        // scratch, so this is the safe default here.
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Deliberately a no-op. Swiping the app away from Recents must NOT
        // stop the alarm — that is the entire point of this service. Do not
        // "fix" this into calling stopSelf()/stopSelfAndCleanUp().
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        mediaPlayer?.release()
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun startForegroundWithNotification(alarmId: String?) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Alarms",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Full-screen alarm notifications that ring until dismissed."
                },
            )
        }

        // Tap-to-return only. The full-screen launch-over-lock-screen job
        // stays exclusively flutter_local_notifications' (its own,
        // unchanged, already-verified notification posted at the same
        // instant) — this notification only needs to survive as the
        // ongoing, non-dismissible, sound-owning one from this point
        // forward, and offer a way back in if tapped.
        val contentIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (alarmId != null) putExtra(MainActivity.ALARM_ID_EXTRA, alarmId)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Motion Alarm")
            .setContentText("Alarmı durdurmak için egzersizi tamamla.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            // No dismiss/snooze action anywhere on this notification — the
            // emergency exit inside the app is the only intentional way out.
            .setContentIntent(contentPendingIntent)
            // Superseding flutter_local_notifications' notification (same
            // id, posted moments earlier) must not re-trigger its channel
            // sound/vibration on top of what this service already started.
            .setOnlyAlertOnce(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startRinging() {
        if (mediaPlayer == null) {
            mediaPlayer = MediaPlayer().apply {
                val afd = resources.openRawResourceFd(R.raw.alarm)
                if (afd != null) {
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                }
                // USAGE_ALARM is exempt from Do Not Disturb by OS design.
                // Deliberately no audio-focus request (unlike the old Dart
                // AudioPlayer default of AUDIOFOCUS_GAIN) so nothing can
                // duck or steal it — matches how AOSP's own Clock app plays
                // its alarm tone.
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                isLooping = true
                prepare()
                start()
            }
        }
        startVibration()
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        // Vibrate immediately, then repeat the 800ms-on/400ms-off segment
        // (index 1 onward) until cancelled — same pattern the old Dart
        // AlarmRingScreen used.
        vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 400), 1))
    }

    private fun setVolumeFraction(fraction: Float) {
        val clamped = fraction.coerceIn(0f, 1f)
        mediaPlayer?.setVolume(clamped, clamped)
        // The alarm's own vibration loop stops here so the single vibration
        // motor is free for clear, distinct per-rep haptic feedback during
        // the exercise — the alarm sound is the only channel that keeps
        // nagging through the whole workout (per CLAUDE.md's volume rule).
        vibrator?.cancel()
    }

    private fun stopSelfAndCleanUp() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
}
