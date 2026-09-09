package com.threadvault.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class DownloadForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Clipora"
        val message = intent?.getStringExtra(EXTRA_MESSAGE) ?: "Saving media…"
        ensureChannels(this)
        startForeground(NOTIFICATION_ID, buildProgressNotification(this, title, message))
        return START_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Clipora:DownloadWakeLock").apply {
            setReferenceCounted(false)
            acquire(30L * 60L * 1000L)
        }
    }

    companion object {
        private const val CHANNEL_ID = "clipora_downloads"
        private const val COMPLETE_CHANNEL_ID = "clipora_download_complete"
        private const val NOTIFICATION_ID = 7107
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_MESSAGE = "message"

        fun start(context: Context, title: String, message: String) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_MESSAGE, message)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun complete(context: Context, title: String, message: String, success: Boolean) {
            ensureChannels(context)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notificationId = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
            manager.notify(notificationId, buildCompleteNotification(context, title, message, success))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadForegroundService::class.java))
        }

        private fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val progress = NotificationChannel(
                CHANNEL_ID,
                "Clipora downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Clipora downloads alive while the app is in the background."
                setShowBadge(false)
            }
            val complete = NotificationChannel(
                COMPLETE_CHANNEL_ID,
                "Clipora finished downloads",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Shows when Clipora has finished saving media."
                setShowBadge(true)
            }
            manager.createNotificationChannel(progress)
            manager.createNotificationChannel(complete)
        }

        private fun buildProgressNotification(context: Context, title: String, message: String): Notification {
            val pendingIntent = launchPendingIntent(context)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            return builder
                .setContentTitle(title)
                .setContentText(message)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .build()
        }

        private fun buildCompleteNotification(context: Context, title: String, message: String, success: Boolean): Notification {
            val pendingIntent = launchPendingIntent(context)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, COMPLETE_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            return builder
                .setContentTitle(title)
                .setContentText(message)
                .setSmallIcon(if (success) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
                .setContentIntent(pendingIntent)
                .setOngoing(false)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_STATUS)
                .build()
        }

        private fun launchPendingIntent(context: Context): PendingIntent {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getActivity(context, 0, launchIntent, flags)
        }
    }
}
