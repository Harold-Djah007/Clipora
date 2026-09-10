package com.threadvault.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object CliporaNotifications {
    const val RESULT_CHANNEL_ID = "clipora_download_results"

    fun ensureResultChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            RESULT_CHANNEL_ID,
            "Clipora save results",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Heads-up alerts when a Clipora save succeeds or fails, including while you are in another app."
            setShowBadge(true)
            enableVibration(true)
            enableLights(true)
        }
        manager.createNotificationChannel(channel)
    }

    fun notifyResult(
        context: Context,
        title: String,
        message: String,
        success: Boolean,
        avoidIds: IntArray = intArrayOf(),
    ) {
        ensureResultChannel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(nextResultId(avoidIds), resultNotification(context, title, message, success))
    }

    fun resultNotification(context: Context, title: String, message: String, success: Boolean): Notification {
        val pendingIntent = launchPendingIntent(context)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, RESULT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.priority = Notification.PRIORITY_HIGH
            @Suppress("DEPRECATION")
            builder.setDefaults(Notification.DEFAULT_ALL)
        }
        return builder
            .setContentTitle(title)
            .setContentText(message)
            .setTicker(title)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setSmallIcon(
                if (success) android.R.drawable.stat_sys_download_done
                else android.R.drawable.stat_notify_error,
            )
            .setContentIntent(pendingIntent)
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(if (success) Notification.CATEGORY_STATUS else Notification.CATEGORY_ERROR)
            .build()
    }

    fun nextResultId(avoidIds: IntArray = intArrayOf()): Int {
        var id = ((System.currentTimeMillis() and 0x7fffffff).toInt() % 1_000_000_000) + 20_000
        if (id == 0 || avoidIds.contains(id)) {
            id = 20_001 + (System.nanoTime() % 100_000).toInt()
        }
        return id
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
