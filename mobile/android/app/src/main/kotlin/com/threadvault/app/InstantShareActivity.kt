package com.threadvault.app

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast

class InstantShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    private fun handleShare(intent: Intent?) {
        val urls = ShareLinks.extractFromIntent(intent)
        if (urls.isEmpty()) {
            Toast.makeText(this, "Clipora needs a link to save.", Toast.LENGTH_SHORT).show()
            closeImmediately()
            return
        }

        val serviceIntent = Intent(this, InstantShareDownloadService::class.java).apply {
            putStringArrayListExtra(InstantShareDownloadService.EXTRA_URLS, ArrayList(urls.take(20)))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        Toast.makeText(
            this,
            if (urls.size == 1) "Clipora is saving in the background." else "Clipora is saving ${urls.size} links in the background.",
            Toast.LENGTH_SHORT,
        ).show()
        if (!notificationsEnabled()) {
            Toast.makeText(
                this,
                "Open Clipora and allow notifications to see save and error alerts.",
                Toast.LENGTH_LONG,
            ).show()
        }
        closeImmediately()
    }

    private fun notificationsEnabled(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val manager = getSystemService(NotificationManager::class.java) ?: return true
            return manager.areNotificationsEnabled()
        }
        return true
    }

    private fun closeImmediately() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            finish()
        }
        overridePendingTransition(0, 0)
    }

    companion object {
        fun shareIntent(context: Context, urls: ArrayList<String>): Intent = Intent(context, InstantShareActivity::class.java).apply {
            putStringArrayListExtra(InstantShareDownloadService.EXTRA_URLS, urls)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
    }
}
